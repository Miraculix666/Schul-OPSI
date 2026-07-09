import unittest
import sys
import io
import runpy
from unittest.mock import MagicMock, patch

class TestRepair(unittest.TestCase):

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
            runpy.run_path('server-scripts/repair.py')

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
            runpy.run_path('server-scripts/repair.py')

        # Assert output
        output = mock_stdout.getvalue()
        self.assertIn("Forced install of", output)
        self.assertIn("succeeded.", output)

if __name__ == '__main__':
    unittest.main()
