"""Native runtime checks and Debug/Release export checks for LLDB helpers."""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'MonkeyAppLibrary.xctemplate/Tools'

@unittest.skipUnless(platform.system() == 'Darwin' and platform.machine() == 'arm64', 'requires Apple Silicon and Xcode')
class LLDBToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='monkeydev-lldb-tools-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def compile(self, sdk='macosx', debug=True, fixture=False):
        sysroot = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
        output = self.root / ('fixture' if fixture else ('debug.dylib' if debug else 'release.dylib'))
        target = 'arm64-apple-macos14.0' if sdk == 'macosx' else 'arm64-apple-ios15.0'
        command = ['xcrun', 'clang++', '-target', target, '-isysroot', sysroot, '-fobjc-arc', '-g', '-O0',
                   '-Wall', '-Wextra', '-Werror', '-I', str(TOOLS), str(TOOLS / 'LLDBTools.mm'), '-framework', 'Foundation']
        if debug: command += ['-DDEBUG=1']
        if sdk == 'iphoneos': command += ['-framework', 'UIKit']
        if fixture: command += [str(ROOT / 'tests/lldb_tools_fixture.m')]
        else: command += ['-dynamiclib']
        result = subprocess.run(command + ['-o', str(output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output

    def test_runtime_metadata_and_invalid_inputs(self):
        output = self.compile(fixture=True)
        result = subprocess.run([str(output)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('[MonkeyDevLLDBTools] PASS', result.stderr)

    def test_device_c_exports_and_release_exclusion(self):
        for debug in [True, False]:
            output = self.compile('iphoneos', debug=debug)
            symbols = subprocess.check_output(['nm', '-gU', str(output)], text=True)
            for function in ['pvc', 'pviews', 'pactions', 'methods', 'ivars', 'md_pvc', 'md_pviews', 'md_pactions', 'md_methods', 'md_ivars']:
                self.assertEqual(' _' + function + '\n' in symbols, debug, symbols)
            for old in ['choose', 'pblock', 'vmmap']:
                self.assertNotIn(' _' + old + '\n', symbols)

if __name__ == '__main__': unittest.main()
