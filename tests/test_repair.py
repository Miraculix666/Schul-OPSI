import unittest
from unittest.mock import patch, MagicMock
import sys
import io
import runpy

class TestRepairScript(unittest.TestCase):
    def setUp(self):
        self.mock_opsicommon_client = MagicMock()
        self.mock_opsi_client_class = MagicMock()
        self.mock_opsicommon_client.OpsiClient = self.mock_opsi_client_class

        self.patcher = patch.dict('sys.modules', {'opsicommon.client': self.mock_opsicommon_client})
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()

    @patch('sys.stdout', new_callable=io.StringIO)
    def test_successful_execution(self, mock_stdout):
        mock_client_instance = MagicMock()
        self.mock_opsi_client_class.return_value = mock_client_instance

        runpy.run_path('server-scripts/repair.py')

        self.mock_opsi_client_class.assert_called_once_with('https://opsi-server-url:4447/rpc', 'admin', 'password')
        mock_client_instance.depot_installProduct.assert_called_once_with('mint22', 'sopsi.lafp.schul.polizei.local', force=True)

        self.assertIn("Forced install of mint22 on sopsi.lafp.schul.polizei.local succeeded.", mock_stdout.getvalue())

    @patch('sys.stdout', new_callable=io.StringIO)
    def test_exception_handling(self, mock_stdout):
        mock_client_instance = MagicMock()
        self.mock_opsi_client_class.return_value = mock_client_instance

        # Make depot_installProduct raise an exception
        mock_client_instance.depot_installProduct.side_effect = Exception("Test exception")

        runpy.run_path('server-scripts/repair.py')

        self.mock_opsi_client_class.assert_called_once_with('https://opsi-server-url:4447/rpc', 'admin', 'password')
        mock_client_instance.depot_installProduct.assert_called_once_with('mint22', 'sopsi.lafp.schul.polizei.local', force=True)

        self.assertIn("Error while forcing install: Test exception", mock_stdout.getvalue())

if __name__ == '__main__':
    unittest.main()
