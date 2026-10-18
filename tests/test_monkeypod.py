"""Check MonkeyPod files can be rendered and consumed as a local CocoaPod."""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'MonkeyPod.xctemplate'

class MonkeyPodTests(unittest.TestCase):
    def test_framework_configuration_and_instance_hook(self):
        data = plistlib.loads((ROOT / 'TemplateInfo.plist').read_bytes())
        s = data['Project']['SharedSettings']
        self.assertEqual(s['IPHONEOS_DEPLOYMENT_TARGET'], '15.0')
        self.assertEqual(s['ARCHS'], 'arm64')
        self.assertNotIn('hasDocumentation', {o['Identifier'] for o in data['Options']})
        self.assertEqual(data['Targets'][0]['ProductType'], 'com.apple.product-type.framework')
        self.assertIn('___PACKAGENAMEASIDENTIFIER___.h', data['Nodes'])
        self.assertEqual(data['Definitions']['___PACKAGENAMEASIDENTIFIER___.podspec']['TargetIndices'], [])
        source = (ROOT / '___PACKAGENAMEASIDENTIFIER___.m').read_text()
        self.assertIn('if (CHClass(CustomViewController))', source)
        self.assertIn('CHHook(0, CustomViewController, getMyName)', source)
        self.assertNotIn('CHClassHook(', source)

    @unittest.skipUnless(shutil.which('pod'), 'requires CocoaPods')
    def test_local_podspec_matches_generated_sources(self):
        with tempfile.TemporaryDirectory(prefix='monkeypod spec ') as work:
            work = Path(work)
            for ext in ('h', 'm', 'podspec'):
                source = ROOT / ('___PACKAGENAMEASIDENTIFIER___.' + ext)
                text = source.read_text().replace('___PACKAGENAMEASIDENTIFIER___', 'Plugin')
                text = text.replace('___PACKAGENAME___', 'Plugin').replace('___FULLUSERNAME___', 'Test')
                (work / ('Plugin.' + ext)).write_text(text)
            (work / 'Extra.mm').write_text('// Objective-C++ plugin source\n')
            result = subprocess.run(['pod', 'ipc', 'spec', str(work / 'Plugin.podspec')],
                                    capture_output=True, text=True, check=True)
            spec = json.loads(result.stdout)
            self.assertEqual(spec['name'], 'Plugin')
            self.assertEqual(spec['platforms']['ios'], '15.0')
            self.assertEqual(spec['public_header_files'], 'Plugin.h')
            self.assertNotIn('static_framework', spec)
            for ext in ('h', 'm', 'mm'):
                self.assertTrue(list(work.glob(spec['source_files'][0].replace('{h,m,mm}', ext))))
            self.assertIn('$(inherited)', spec['pod_target_xcconfig']['HEADER_SEARCH_PATHS'])
