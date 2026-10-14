"""Offline checks for identifiable administrative/smoke HTTP clients; no credentials/network."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

def module(name):
    path=Path(__file__).with_name(name+".py")
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

class HttpClients(unittest.TestCase):
    def test_smoke_identifies_itself_without_replacing_authentication(self):
        client=module("mail_deployment_smoke")
        response=MagicMock()
        response.__enter__.return_value.read.return_value=b"{}"
        with patch.object(client.urllib.request,"urlopen",return_value=response) as opening:
            client.request_json("https://example.invalid",{},{"Authorization":"Bearer test-only"})
            request=opening.call_args.args[0]
            self.assertEqual(request.get_header("User-agent"),"Tapped-Mail-Deployment-Smoke/1.0")
            self.assertEqual(request.get_header("Authorization"),"Bearer test-only")

    def test_backfill_signed_ingress_keeps_signature_and_identifies_itself(self):
        client=module("backfill_mail_threads")
        response=MagicMock()
        response.__enter__.return_value.status=204
        with patch.object(client.urllib.request,"urlopen",return_value=response) as opening:
            client.send_record("https://example.invalid","test-only","threads",{"id":"synthetic"})
            request=opening.call_args.args[0]
            self.assertEqual(request.get_header("User-agent"),"Tapped-Mail-Backfill/1.0")
            self.assertTrue(request.get_header("X-tapped-signature"))
            self.assertTrue(request.get_header("X-tapped-timestamp"))

if __name__=="__main__":
    unittest.main()
