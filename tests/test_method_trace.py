from pathlib import Path
import re
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / 'MonkeyAppLibrary.xctemplate/Trace'

@unittest.skipUnless(platform.system() == 'Darwin' and platform.machine() == 'arm64', 'requires Apple Silicon')
class MethodTraceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='monkeydev-method-trace-')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def compile(self, sdk='macosx', debug=True, fixture=False):
        target = 'arm64-apple-macos14.0' if sdk == 'macosx' else 'arm64-apple-ios15.0'
        sysroot = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
        output = self.path / ('fixture' if fixture else ('debug.dylib' if debug else 'release.dylib'))
        command = ['xcrun', 'clang++', '-target', target, '-isysroot', sysroot, '-std=c++17', '-fobjc-arc',
                   '-Wall', '-Wextra', '-Werror', '-I', str(TRACE), str(TRACE / 'MDMethodTrace.mm'), '-framework', 'Foundation']
        if debug: command += ['-DDEBUG=1']
        if fixture: command += [str(ROOT / 'tests/method_trace_fixture.mm')]
        else: command += ['-dynamiclib']
        result = subprocess.run(command + ['-o', str(output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output

    def test_abi_and_runtime(self):
        output = self.compile(fixture=True)
        result = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('[MonkeyDevTraceTest] PASS', result.stderr)
        self.assertRegex(result.stderr, r'args depth=0 call=\d+ thread=\d+ -\[MDTraceChild integer:\] arg1=-9')
        self.assertRegex(result.stderr, r'return depth=0 call=\d+ thread=\d+ -\[MDTraceChild integer:\] -20')
        self.assertRegex(result.stderr, r'args depth=0 call=\d+ thread=\d+ -\[MDTraceChild pair:other:\] arg1=nil \| arg2=<NSObject:')
        self.assertIn('trace-value\\nsecond-line', result.stderr)
        self.assertIn('…<truncated>', result.stderr)
        self.assertNotIn('A' * 513, result.stderr)
        self.assertIn('<description threw MDTraceDescriptionFailure>', result.stderr)
        self.assertIn('nested-value=9', result.stderr)
        self.assertRegex(result.stderr, r'return depth=0 call=\d+ thread=\d+ -\[MDTraceChild ping\] void')
        self.assertRegex(result.stderr, r'before depth=1 call=\d+ thread=\d+ -\[MDTraceChild integer:\]')
        calls = {}
        for event, depth, call_id, thread in re.findall(
            r'\[MonkeyDevTrace\] (before|args|return|after|after-throw) depth=(\d+) call=(\d+) thread=(\d+)', result.stderr
        ):
            calls.setdefault(call_id, []).append((event, depth, thread))
        self.assertGreater(len(calls), 100)
        for records in calls.values():
            events = [r[0] for r in records]
            self.assertEqual(events, ['before', 'args', 'after-throw'] if events[-1] == 'after-throw' else ['before', 'args', 'return', 'after'])
            self.assertEqual(len({r[1:] for r in records}), 1)
            self.assertNotEqual(records[0][2], '0')

    def test_device_exports_and_release_exclusion(self):
        for debug in [True, False]:
            output = self.compile('iphoneos', debug=debug)
            symbols = subprocess.check_output(['nm', '-gU', str(output)], text=True, stderr=subprocess.DEVNULL)
            for name in ['md_trace_start', 'md_trace_stop', 'md_trace_status', 'md_trace_set_descriptions']:
                self.assertEqual(' _' + name + '\n' in symbols, debug)
            loads = subprocess.check_output(['otool', '-L', str(output)], text=True)
            self.assertNotIn('substrate', loads.lower())
            self.assertNotIn('cycript', loads.lower())

if __name__ == '__main__': unittest.main()
