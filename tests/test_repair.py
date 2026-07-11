import unittest
import sys
import io
import runpy
import os
from unittest.mock import MagicMock, patch

class TestRepair(unittest.TestCase):

    def setUp(self):
        # Set environment variables required by repair.py
        os.environ['OPSI_USER'] = 'testuser'
        os.environ['OPSI_PASSWORD'] = 'testpassword'

    def tearDown(self):
        # Clean up environment variables
        if 'OPSI_USER' in os.environ:
            del os.environ['OPSI_USER']
        if 'OPSI_PASSWORD' in os.environ:
            del os.environ['OPSI_PASSWORD']

        # Clean up any compiled Python files generated during the test run
        try:
            os.remove('scripts-and-tools-OPSI/server-scripts/__pycache__/repair.cpython-312.pyc')
            os.rmdir('scripts-and-tools-OPSI/server-scripts/__pycache__')
        except FileNotFoundError:
            pass

    @patch('sys.stdout', new_callable=io.StringIO)
    def test_repair_exception_handling(self, mock_stdout):
        # Mock opsicommon.client
        mock_opsicommon_client = MagicMock()
        mock_OpsiClient_class = MagicMock()
        mock_client_instance = MagicMock()

        mock_OpsiClient_class.return_value = mock_client_instance
        mock_opsicommon_client.OpsiClient = mock_OpsiClient_class

        # Simulate exception
        mock_client_instance.depot_installProduct.side_effect = Exception("Simulated error")

        with patch.dict('sys.modules', {'opsicommon.client': mock_opsicommon_client, 'opsicommon': MagicMock()}):
            # Run the script
            runpy.run_path('scripts-and-tools-OPSI/server-scripts/repair.py')

        # Assert output
        output = mock_stdout.getvalue()
        self.assertIn("Error while forcing install: Simulated error", output)

    @patch('sys.stdout', new_callable=io.StringIO)
    def test_repair_success(self, mock_stdout):
        # Mock opsicommon.client
        mock_opsicommon_client = MagicMock()
        mock_OpsiClient_class = MagicMock()
        mock_client_instance = MagicMock()

        mock_OpsiClient_class.return_value = mock_client_instance
        mock_opsicommon_client.OpsiClient = mock_OpsiClient_class

        with patch.dict('sys.modules', {'opsicommon.client': mock_opsicommon_client, 'opsicommon': MagicMock()}):
            # Run the script
            runpy.run_path('scripts-and-tools-OPSI/server-scripts/repair.py')

        # Assert output
        output = mock_stdout.getvalue()
        self.assertIn("Forced install of", output)
        self.assertIn("succeeded.", output)

if __name__ == '__main__':
    unittest.main()
