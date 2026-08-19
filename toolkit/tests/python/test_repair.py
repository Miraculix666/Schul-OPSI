import sys
from unittest.mock import MagicMock
import runpy
import os
import pytest

# Setup global mock for opsicommon because the module is not available locally
mock_opsicommon = MagicMock()
sys.modules['opsicommon'] = mock_opsicommon
sys.modules['opsicommon.client'] = mock_opsicommon.client

@pytest.fixture(autouse=True)
def reset_mocks():
    mock_opsicommon.reset_mock()
    mock_opsicommon.client.OpsiClient.reset_mock()
    yield

def test_repair_success(capsys):
    mock_client_instance = MagicMock()
    mock_opsicommon.client.OpsiClient.return_value = mock_client_instance

    script_path = os.path.join(os.path.dirname(__file__), 'repair.py')
    runpy.run_path(script_path)

    mock_client_instance.depot_installProduct.assert_called_with(
        'mint22', 'sopsi.lafp.schul.polizei.local', force=True
    )
    captured = capsys.readouterr()
    assert "Forced install of mint22 on sopsi.lafp.schul.polizei.local succeeded." in captured.out

def test_repair_error(capsys):
    mock_client_instance = MagicMock()
    mock_opsicommon.client.OpsiClient.return_value = mock_client_instance

    test_exception = Exception("Test connection error")
    mock_client_instance.depot_installProduct.side_effect = test_exception

    script_path = os.path.join(os.path.dirname(__file__), 'repair.py')
    runpy.run_path(script_path)

    mock_client_instance.depot_installProduct.assert_called_with(
        'mint22', 'sopsi.lafp.schul.polizei.local', force=True
    )
    captured = capsys.readouterr()
    assert "Error while forcing install:" in captured.out
    assert "Test connection error" in captured.out
