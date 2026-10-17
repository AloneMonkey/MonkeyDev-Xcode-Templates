"""Check the vendored upstream fishhook on current arm64 linkers."""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'MonkeyAppLibrary.xctemplate/fishhook'

@unittest.skipUnless(platform.system() == 'Darwin' and platform.machine() == 'arm64', 'requires Apple Silicon')
class FishhookTests(unittest.TestCase):
    def test_import_rebinding_and_original_call(self):
        with tempfile.TemporaryDirectory(prefix='monkeydev-fishhook-') as temp:
            for name, flags in [('chained', []), ('legacy', ['-Wl,-no_fixup_chains'])]:
                with self.subTest(format=name):
                    binary = Path(temp) / name
                    result = subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-macos14.0',
                        '-O0', '-fno-builtin', '-I', str(SOURCE), str(ROOT / 'tests/fishhook_fixture.c'),
                        str(SOURCE / 'fishhook.c'), *flags, '-o', str(binary)], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('[MonkeyDevFishhook] PASS', result.stderr)

    def test_iphoneos_arm64_build(self):
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        with tempfile.TemporaryDirectory(prefix='monkeydev-fishhook-ios-') as temp:
            binary = Path(temp) / 'libFishhookCheck.dylib'
            result = subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-ios15.0', '-isysroot', sdk,
                '-O0', '-fno-builtin', '-dynamiclib', '-DMD_FISHHOOK_DYLIB=1', '-I', str(SOURCE),
                str(ROOT / 'tests/fishhook_fixture.c'), str(SOURCE / 'fishhook.c'), '-o', str(binary)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip(), 'arm64')

if __name__ == '__main__': unittest.main()
