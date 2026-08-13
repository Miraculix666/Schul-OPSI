# OPSI-Agent: Schul-OPSI Deployment (agent.md)
*This file contains specialized instructions, inventory, and workflows for OPSI deployment and client management.*

## 🧠 Core System Intelligence

### 🏗️ Architectural Patterns
- **Identity & Focus**: Open PC Server Integration (OPSI) package management and system configuration scripts.
- **Client Management**: Automated deployment of the OPSI client agent, Windows package installations, and registry optimizations.
- **Verification Standard**: Always validate script execution paths and check dependency existence before executing package pushes.

### 🛠️ Specialized Workflows
- **Unattended Executions**: All deployment modules must support silent/non-interactive installation options (e.g. `--silent`, `-qn`).
- **Log Collection**: Detailed logging of installer return codes and diagnostic outputs.
