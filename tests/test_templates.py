"""Validate complete release templates without applying installer patches."""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]

class TemplateTests(unittest.TestCase):
    def load(self, name):
        return plistlib.loads((ROOT / (name + '.xctemplate/TemplateInfo.plist')).read_bytes())

    def test_arm64_settings_and_script_shells(self):
        for name in ['Base', 'MonkeyApp', 'MonkeyAppLibrary']:
            with self.subTest(template=name):
                data = self.load(name)
                project = data['Project']['SharedSettings']
                self.assertEqual(project['MonkeyDevTheosPath'], '$(HOME)/theos')
                self.assertNotIn('/**', project['HEADER_SEARCH_PATHS'])
                self.assertNotIn('/opt/theos', str(data))
                for settings in [project] + [target['SharedSettings'] for target in data['Targets']]:
                    self.assertEqual(settings['ARCHS'], 'arm64')
                    self.assertEqual(settings['SUPPORTED_PLATFORMS'], 'iphoneos')
                    self.assertEqual(settings['IPHONEOS_DEPLOYMENT_TARGET'], '15.0')
                    self.assertEqual(settings['ENABLE_USER_SCRIPT_SANDBOXING'], 'NO')
                for target in data['Targets']:
                    for phase in target.get('BuildPhases', []):
                        if phase['Class'] == 'ShellScript':
                            self.assertEqual(phase['ShellPath'], '/bin/bash')

    def test_app_options_and_incremental_signing(self):
        data = self.load('MonkeyApp')
        target = data['Targets'][0]
        settings = target['SharedSettings']
        self.assertEqual(settings['GENERATE_INFOPLIST_FILE'], 'NO')
        self.assertEqual(settings['INFOPLIST_FILE'], '___PACKAGENAME___/Info.plist')
        self.assertEqual(settings['ENABLE_DEBUG_DYLIB'], 'NO')
        self.assertEqual(settings['MONKEYDEV_MINIMAL'], 'YES')
        self.assertNotIn('MONKEYDEV_ADD_SUBSTRATE', settings)
        self.assertEqual(settings['EXCLUDED_SOURCE_FILE_NAMES'], '$(inherited) *.ipa *.app')
        options = {option['Identifier']: option for option in data['Options']}
        for identifier, setting, default in [
            ('mdInsertDylib', 'MONKEYDEV_INSERT_DYLIB', 'YES'),
            ('mdKeepBundleID', 'MONKEYDEV_DEFAULT_BUNDLEID', 'NO'),
            ('mdRestoreSymbols', 'MONKEYDEV_RESTORE_SYMBOL', 'NO'),
            ('mdExportHeaders', 'MONKEYDEV_CLASS_DUMP', 'NO'),
        ]:
            option = options[identifier]
            self.assertEqual(option['Type'], 'popup')
            self.assertEqual(option['Values'], ['YES', 'NO'])
            self.assertEqual(option['Default'], default)
            self.assertTrue(option['NotPersisted'])
            self.assertEqual(settings[setting], '___VARIABLE_' + identifier + '___')
        inspector = options['mdUIInspector']
        self.assertEqual(inspector['Values'], ['None', 'Reveal', 'Lookin'])
        self.assertEqual(inspector['Default'], 'None')
        self.assertTrue(inspector['NotPersisted'])
        self.assertEqual(settings['MONKEYDEV_UI_INSPECTOR'], '___VARIABLE_mdUIInspector___')
        self.assertNotIn('MONKEYDEV_REVEAL', settings)
        signing = [phase for phase in target['BuildPhases']
                   if phase.get('ShellScript', '').endswith('/Tools/pack.sh codesign')]
        self.assertEqual(len(signing), 1)
        self.assertNotIn('InputFiles', signing[0])
        self.assertNotIn('OutputFiles', signing[0])
        self.assertNotIn('Cycript', plistlib.loads((ROOT / 'MonkeyApp.xctemplate/Config/MDConfig.plist').read_bytes()))

    def test_library_sources_and_compile_membership(self):
        data = self.load('MonkeyAppLibrary')
        library = ROOT / 'MonkeyAppLibrary.xctemplate'
        settings = data['Targets'][0]['SharedSettings']
        self.assertEqual(settings['OTHER_LDFLAGS'], '$(inherited)')
        self.assertEqual(settings['INSTALL_PATH'], '@executable_path/Frameworks')
        self.assertEqual(settings['CLANG_CXX_LANGUAGE_STANDARD'], 'gnu++17')
        debug = data['Project']['Configurations']['Debug']
        self.assertEqual(debug['OTHER_LDFLAGS'], '$(inherited)')
        self.assertEqual(debug['GCC_PREPROCESSOR_DEFINITIONS'], '$(inherited) DEBUG=1')
        for node in data['Nodes']:
            self.assertFalse(node.startswith(('Config/', 'AntiAntiDebug/')))
        for source in ['fishhook/fishhook.c', 'fishhook/fishhook.h', 'Tools/LLDBTools.h',
                       'Tools/LLDBTools.mm', 'Trace/MDMethodTrace.h', 'Trace/MDMethodTrace.mm']:
            self.assertIn(source, data['Nodes'])
            self.assertTrue((library / source).is_file())
            self.assertEqual(data['Definitions'][source]['TargetIndices'],
                             [] if source.endswith('.h') else [0])
        xm = 'Logos/___PACKAGENAMEASIDENTIFIER___.xm'
        self.assertEqual(data['Definitions'][xm]['FileType'], 'sourcecode.cpp.objcpp')
        self.assertEqual(data['Definitions'][xm]['TargetIndices'], [])
        self.assertIn('%config(generator=internal)', (library / xm).read_text())
        self.assertIn('#import <CaptainHook/CaptainHook.h>',
                      (library / '___PACKAGENAMEASIDENTIFIER___.m').read_text())
        for name in ['MDCycriptManager.h', 'MDCycriptManager.m']:
            self.assertFalse((library / 'Config' / name).exists())
            self.assertNotIn('Config/' + name, data['Definitions'])

if __name__ == '__main__':
    unittest.main()
