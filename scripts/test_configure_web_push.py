import json
from pathlib import Path
import tempfile
import unittest

from configure_web_push import generate


class WebPushConfigurationTest(unittest.TestCase):
    def test_generates_matching_public_config_and_defines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'web').mkdir()
            config = {'apiKey': 'public-api', 'appId': 'web-app',
                      'messagingSenderId': 'sender', 'projectId': 'project',
                      'vapidKey': 'public-vapid'}
            source = root / 'input.json'
            source.write_text(json.dumps(config))
            generate(source, root)
            defines = json.loads((root / 'firebase.web.env.json').read_text())
            worker = (root / 'web/firebase-public-config.js').read_text()
            worker_config = json.loads(worker.split('self.firebasePublicConfig = ')[1].rstrip(';\n'))
            self.assertEqual(defines['FIREBASE_PROJECT_ID'], worker_config['projectId'])
            self.assertEqual(defines['FIREBASE_APP_ID'], worker_config['appId'])
            self.assertEqual(defines['FIREBASE_VAPID_KEY'], 'public-vapid')
            self.assertEqual(defines['PUSH_ENABLED'], 'true')
            self.assertNotIn('vapidKey', worker_config)

    def test_rejects_service_account_before_writing_anything(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'web').mkdir()
            source = root / 'input.json'
            source.write_text(json.dumps({'private_key': 'secret'}))
            with self.assertRaisesRegex(ValueError, 'never a service-account'):
                generate(source, root)
            self.assertFalse((root / 'web/firebase-public-config.js').exists())
            self.assertFalse((root / 'firebase.web.env.json').exists())

    def test_rejects_missing_vapid_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'input.json'
            source.write_text(json.dumps({'apiKey': 'api', 'appId': 'app',
                                         'messagingSenderId': 'id', 'projectId': 'project'}))
            with self.assertRaisesRegex(ValueError, 'vapidKey'):
                generate(source, root)


if __name__ == '__main__':
    unittest.main()
