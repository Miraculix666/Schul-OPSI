import unittest
from unittest.mock import MagicMock, patch
import sys
import io
from contextlib import redirect_stdout
import runpy
import os

class TestRepair(unittest.TestCase):

    @patch.dict('sys.modules', {'opsicommon': MagicMock(), 'opsicommon.client': MagicMock()})
    def test_repair_exception_handling(self):
        # Retrieve the mocked modules that patch.dict inserted
        mock_opsicommon = sys.modules['opsicommon']
        mock_client_module = sys.modules['opsicommon.client']

        # Set up the mock OpsiClient class and instance
        mock_OpsiClient_class = MagicMock()
        mock_client_instance = MagicMock()
        mock_OpsiClient_class.return_value = mock_client_instance

        # Link the class to the client module mock
        mock_client_module.OpsiClient = mock_OpsiClient_class

        # Make depot_installProduct raise an exception
        mock_client_instance.depot_installProduct.side_effect = Exception("Mock error")

        # Get absolute path to the script so it can be run
        script_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'server-scripts', 'repair.py'))

        # Capture stdout using contextlib
        captured_output = io.StringIO()
        with redirect_stdout(captured_output):
            # Execute the script
            runpy.run_path(script_path)

        output = captured_output.getvalue()

        # Check that the exception was caught and printed
        self.assertIn("Error while forcing install:", output)
        self.assertIn("Mock error", output)

if __name__ == '__main__':
    unittest.main()
