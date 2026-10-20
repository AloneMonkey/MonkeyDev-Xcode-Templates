"""Logos Tweak template defaults and selectable package layout."""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]

class LogosTweakTests(unittest.TestCase):
    def test_tweak_defaults_and_layouts(self):
        data = plistlib.loads((ROOT / 'Logos Tweak.xctemplate/TemplateInfo.plist').read_bytes())
        target = data['Targets'][0]
        settings = target['SharedSettings']
        self.assertNotIn('CydiaSubstrate', target['Frameworks'])
        self.assertIn('-lsubstrate', settings['OTHER_LDFLAGS'])
        self.assertIn('/var/jb/Library/Frameworks', settings['MONKEYDEV_TWEAK_RPATH_rootless'].split())
        self.assertEqual(settings['MONKEYDEV_PACKAGE_PREFIX_rootless'], '/var/jb')
        self.assertEqual(settings['MONKEYDEV_PACKAGE_PREFIX_rootful'], '')
        self.assertIn('/iphone/rootless', settings['MONKEYDEV_TWEAK_LIB_rootless'])
        for setting in ('MonkeyDevInstallOnProfiling', 'CODE_SIGNING_ALLOWED'):
            self.assertEqual(settings[setting], 'NO')
        self.assertEqual(settings['MonkeyDevBuildPackageOnAnyBuild'], 'YES')
        self.assertEqual(settings['MonkeyDevkillProcessOnInstall'], '')
        xm = data['Definitions']['___PACKAGENAMEASIDENTIFIER___.xm']
        self.assertEqual(xm['FileType'], 'sourcecode.cpp.objcpp')
        self.assertEqual(xm['TargetIndices'], [])

    def test_minimal_wizard_defaults(self):
        data = plistlib.loads((ROOT / 'Logos Tweak.xctemplate/TemplateInfo.plist').read_bytes())
        options = {o['Identifier']: o for o in data['Options']}
        self.assertEqual(set(options), {'mdPackageScheme', 'mdAuthentication', 'mdSSHUser', 'mdSSHPassword'})
        self.assertEqual(options['mdAuthentication']['Values'], ['None', 'KEY', 'PASSWORD'])
        self.assertEqual(options['mdAuthentication']['Default'], 'KEY')
        settings = data['Targets'][0]['SharedSettings']
        self.assertEqual(settings['MONKEYDEV_PACKAGE_SCHEME'], '___VARIABLE_mdPackageScheme___')
        self.assertEqual(options['mdPackageScheme']['Values'], ['rootless', 'rootful', 'roothide'])
        self.assertEqual(options['mdPackageScheme']['Default'], 'rootless')
        self.assertTrue(options['mdPackageScheme']['NotPersisted'])
        self.assertEqual(settings['MONKEYDEV_PACKAGE_PREFIX_roothide'], '')
        self.assertIn('/Librarys/roothide', settings['MONKEYDEV_TWEAK_LIB_roothide'])
        self.assertNotIn('/var/jb', settings['MONKEYDEV_TWEAK_RPATH_roothide'])
        self.assertIn('@loader_path/.jbroot/', settings['MONKEYDEV_TWEAK_INSTALL_NAME_roothide'])
        self.assertEqual(settings['MonkeyDevConnectionType'], 'USB')
        self.assertEqual(settings['MonkeyDevDeviceUDID'], '')
        self.assertEqual(settings['MonkeyDevDeviceKey'], '')

    def test_password_fields_are_conditional_and_not_remembered(self):
        data = plistlib.loads((ROOT / 'Logos Tweak.xctemplate/TemplateInfo.plist').read_bytes())
        options = {o['Identifier']: o for o in data['Options']}
        for name in ('mdSSHUser', 'mdSSHPassword'):
            self.assertEqual(options[name]['RequiredOptions'], {'mdAuthentication': 'PASSWORD'})
            self.assertTrue(options[name]['NotPersisted'])
            self.assertTrue(options[name]['Required'])
        settings = data['Targets'][0]['SharedSettings']
        self.assertEqual(settings['MONKEYDEV_SSH_USER_KEY'], '')
        self.assertEqual(settings['MONKEYDEV_SSH_PASSWORD_KEY'], '')
        self.assertEqual(settings['MONKEYDEV_SSH_PASSWORD_PASSWORD'], '___VARIABLE_mdSSHPassword___')
        self.assertEqual(settings['MonkeyDevDevicePassword'], '$(MONKEYDEV_SSH_PASSWORD_$(MonkeyDevAuthentication))')

    def test_installation_follows_authentication_choice(self):
        data = plistlib.loads((ROOT / 'Logos Tweak.xctemplate/TemplateInfo.plist').read_bytes())
        s = data['Targets'][0]['SharedSettings']
        self.assertEqual(s['MonkeyDevInstallOnAnyBuild'], '$(MONKEYDEV_INSTALL_$(MonkeyDevAuthentication))')
        for auth, enabled in [('None', 'NO'), ('KEY', 'YES'), ('PASSWORD', 'YES')]:
            self.assertEqual(s['MONKEYDEV_INSTALL_' + auth], enabled)
        self.assertEqual(s['MONKEYDEV_SSH_USER_None'], '')
        self.assertEqual(s['MONKEYDEV_SSH_PASSWORD_None'], '')

    def test_captainhook_package_schemes_without_substrate_linking(self):
        d = plistlib.loads((ROOT / 'CaptainHook Tweak.xctemplate/TemplateInfo.plist').read_bytes())
        s = d['Targets'][0]['SharedSettings']
        self.assertEqual(d['Options'][0]['Values'], ['rootless', 'rootful', 'roothide'])
        self.assertEqual(d['Options'][0]['Default'], 'rootless')
        self.assertEqual(s['MONKEYDEV_PACKAGE_SCHEME'], '___VARIABLE_mdPackageScheme___')
        self.assertEqual(s['MONKEYDEV_PACKAGE_PREFIX_roothide'], '')
        self.assertEqual(s['MONKEYDEV_TWEAK_INSTALL_NAME_roothide'],
                         '@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/$(EXECUTABLE_PATH)')
        self.assertEqual(s['LD_DYLIB_INSTALL_NAME'], '$(MONKEYDEV_TWEAK_INSTALL_NAME_$(MONKEYDEV_PACKAGE_SCHEME))')
        self.assertNotIn('-lsubstrate', s.get('OTHER_LDFLAGS', ''))
        self.assertNotIn('CHUseSubstrate', (ROOT / 'CaptainHook Tweak.xctemplate/___PACKAGENAMEASIDENTIFIER___.mm').read_text())

    def test_command_tool_roothide_layout_without_hook_libraries(self):
        d = plistlib.loads((ROOT / 'Command-line Tool.xctemplate/TemplateInfo.plist').read_bytes())
        s = d['Targets'][0]['SharedSettings']
        self.assertEqual(d['Options'][1]['Values'], ['rootless', 'rootful', 'roothide'])
        self.assertEqual(d['Options'][1]['Default'], 'rootless')
        self.assertEqual(s['MONKEYDEV_PACKAGE_SCHEME'], '___VARIABLE_mdPackageScheme___')
        self.assertEqual(s['MONKEYDEV_PACKAGE_PREFIX_roothide'], '')
        self.assertEqual(s['INSTALL_PATH'], '$(MONKEYDEV_PACKAGE_PREFIX)/usr/bin')
        self.assertNotIn('LD_DYLIB_INSTALL_NAME', s)
        self.assertNotIn('-lsubstrate', s['OTHER_LDFLAGS'])

    def test_path_sdk_is_available_in_all_jailbreak_templates(self):
        for name in ('Logos Tweak', 'CaptainHook Tweak', 'Command-line Tool'):
            with self.subTest(template=name):
                d = plistlib.loads((ROOT / (name + '.xctemplate') / 'TemplateInfo.plist').read_bytes())
                s = d['Targets'][0]['SharedSettings']
                self.assertIn('$(MONKEYDEV_ROOTHIDE_INCLUDE_$(MONKEYDEV_PACKAGE_SCHEME))', s['HEADER_SEARCH_PATHS'])
                self.assertEqual(s['MONKEYDEV_ROOTHIDE_INCLUDE_roothide'], '$(MonkeyDevPath)/Librarys/roothide/include')
                self.assertIn('$(MONKEYDEV_ROOTHIDE_LIB_$(MONKEYDEV_PACKAGE_SCHEME))', s['LIBRARY_SEARCH_PATHS'])
                self.assertNotIn('roothide', s['OTHER_LDFLAGS'])
                self.assertNotIn('dead_strip_dylibs', s['OTHER_LDFLAGS'])
                self.assertIn('$(MONKEYDEV_ROOTHIDE_CFLAGS_$(MONKEYDEV_PACKAGE_SCHEME))', s['OTHER_CFLAGS'])
                self.assertIn('$(OTHER_CFLAGS)', s['OTHER_CPLUSPLUSFLAGS'])
                self.assertIn('$(MONKEYDEV_ROOTHIDE_DEFINES_$(MONKEYDEV_PACKAGE_SCHEME))', s['GCC_PREPROCESSOR_DEFINITIONS'])
                self.assertEqual(s['MONKEYDEV_ROOTHIDE_CFLAGS_roothide'], '-fmodules')
                self.assertEqual(s['MONKEYDEV_ROOTHIDE_CXXFLAGS_roothide'], '-fcxx-modules')
                self.assertEqual(s['MONKEYDEV_ROOTHIDE_DEFINES_roothide'], 'THEOS_PACKAGE_SCHEME_ROOTHIDE=1')
                for scheme in ('rootless', 'rootful'):
                    self.assertEqual(s['MONKEYDEV_ROOTHIDE_DEFINES_' + scheme], '')
                    self.assertEqual(s['MONKEYDEV_ROOTHIDE_INCLUDE_' + scheme], '')
                    self.assertEqual(s['MONKEYDEV_ROOTHIDE_LIB_' + scheme], '')
                    self.assertEqual(s['MONKEYDEV_ROOTHIDE_CFLAGS_' + scheme], '')
                    self.assertEqual(s['MONKEYDEV_ROOTHIDE_CXXFLAGS_' + scheme], '')

    def test_other_jailbreak_templates_share_install_options(self):
        logos = plistlib.loads((ROOT / 'Logos Tweak.xctemplate/TemplateInfo.plist').read_bytes())
        for name in ('CaptainHook Tweak', 'Command-line Tool'):
            with self.subTest(template=name):
                d = plistlib.loads((ROOT / (name + '.xctemplate') / 'TemplateInfo.plist').read_bytes())
                s = d['Targets'][0]['SharedSettings']
                self.assertEqual(s['MonkeyDevInstallOnAnyBuild'], logos['Targets'][0]['SharedSettings']['MonkeyDevInstallOnAnyBuild'])
                self.assertEqual(s['CODE_SIGNING_ALLOWED'], 'NO')
                self.assertEqual(s['MonkeyDevConnectionType'], 'USB')
                self.assertNotIn('CydiaSubstrate', d['Targets'][0].get('Frameworks', []))
                self.assertNotIn('-lsubstrate', s.get('OTHER_LDFLAGS', ''))
                self.assertEqual(d['Options'][-3:], logos['Options'][-3:])
                for phase in d['Targets'][0]['BuildPhases']:
                    if phase['Class'] == 'ShellScript':
                        self.assertEqual(phase['ShellPath'], '/bin/bash')
                        self.assertFalse(phase['ShowEnvVarsInLog'])
        tool = plistlib.loads((ROOT / 'Command-line Tool.xctemplate/TemplateInfo.plist').read_bytes())
        self.assertNotIn('Core Services', tool['Options'][0]['Units'])
        self.assertEqual(set(tool['Options'][0]['Units']), {'C', 'C++', 'Foundation', 'Core Foundation'})
        self.assertNotIn('Package/usr/bin/0xdeadfa11', tool['Nodes'])
        self.assertNotIn('Package/usr/bin/0xdeadfa11', tool['Definitions'])
        self.assertEqual(plistlib.loads((ROOT / 'Command-line Tool.xctemplate/monkeydev.entitlements').read_bytes()), {})
