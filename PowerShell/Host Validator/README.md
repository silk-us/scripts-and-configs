# Silk Host Validator

Validate Windows and Linux host configurations against **Silk best practices** for cloud deployments using the PowerShell script **`Silk_DotC_Validator.ps1`**. The validator can be run from **Windows or Linux**, can validate **one or many hosts**, and generates a consolidated **HTML report** with recommendations.

## Table of Contents

- [Overview](#overview)
- [What’s New](#whats-new)
- [Important Note](#important-note)
- [Silk Best Practices Guides](#silk-best-practices-guides)
- [Prerequisites](#prerequisites)
- [Example Usage](#example-usage)
  - [Validate local Windows machine](#validate-local-windows-machine)
  - [Validate a remote Windows host (WinRM)](#validate-a-remote-windows-host-winrm)
  - [Validate Linux hosts over SSH from Windows (Posh-SSH)](#validate-linux-hosts-over-ssh-from-windows-posh-ssh)
  - [Validate from Linux](#run-from-linux)
- [Validations Performed](#validations-performed)
- [Output](#output)
- [Limitations](#limitations)
- [Support](#support)

---

## Overview

The Silk Host Validator verifies host configuration against Silk best practices for cloud deployments.

- Runs on **Windows and Linux**
- Validates **Windows and Linux** hosts
- Supports **single or multi-host** execution
- Produces a consolidated **HTML report**

---

## What’s New

- Major script rewrite
- Modern HTML report (cards, badges, recommendations)
- Multi-host, remote validation with aggregated results
- Cross-platform execution
- Enhanced checks for iSCSI, MPIO, TRIM/UNMAP, control LUN, and udev rules

---

## Important Note

Validation results are **informational guidance** intended to help align configurations with Silk-supported best practices.  
If recommendations conflict with other vendor requirements, consult **Silk Support** before making changes.

---

## Silk Best Practices Guides

Refer to the **Silk Documentation Portal** for the latest guidance on SDP connectivity & host best practices.



## Prerequisites

- PowerShell 7.x (Windows or Linux)
- Administrative or root privileges

### Remote Windows Hosts (to be validated from a different Windows host)
- PowerShell remoting (enabled by default on Windows Server platforms): 
```powershell
Enable-PSRemoting -Force
```
- WinRM ports: 5985 unencrypted / 5986 encrypted

### Remote Linux Hosts (to be validated from a different Windows or Linux host)
- SSH access (port 22)
- From Windows: install **Posh-SSH**
- From Linux: OpenSSH client is used
- Optional SSH key file via `-KeyFile`



## Example Usage

### Validate a local Windows host

```powershell
.\Silk_DotC_Validator.ps1 -HostType Windows
```

---

### Validate a remote Windows host (WinRM)

```powershell
.\Silk_DotC_Validator.ps1 -HostType Windows -Hosts "WIN-SQL01"
```

---

### Validate Linux hosts over SSH from Windows (Posh-SSH)

```powershell
Install-Module -Name Posh-SSH

.\Silk_DotC_Validator.ps1 -HostType Linux -Hosts "rhel01 10.0.1.25" -User ec2-user -KeyFile C:\keys\silk.pem
```

---

### Validate from Linux

```bash
pwsh /path/to/Silk_DotC_Validator.ps1 -HostType Linux -Hosts "rhel01 rhel02" -User ec2-user -KeyFile ~/.ssh/key.pem
```

---

## Validations Performed

- System Information
- iSCSI Service
- MPIO Settings
- Silk Disks
- Control LUN
- TRIM / UNMAP & Defrag
- iSCSI Sessions & Scaling
- Networking (RSC & NICs)

---

## Output

An HTML report is generated:

```
SDP_Host_Validation_<MM-dd-yyyy_HH-mm-ss>.html
```

### Status Legend

- **OK** – Configured as recommended
- **WARN** – Not fully aligned
- **ERR** – Missing or misconfigured
- **INFO** – Informational data

---

## Limitations

- Linux hosts cannot validate Windows hosts
- WinRM must be properly configured for Windows remote validation
- Posh-SSH required for Linux host validation from Windows hosts

---

## Support

Silk Support is available via:

- [Support Portal](https://support.silk.us/aspx/CustomLoginPage "Login Page | Silk Portal | Silk")
- [Clarity Dashboard](https://clarity.silk.us "Silk Login")

Phone numbers:
- US: [+1 877 982 2555](tel:+18779822555) 
- UK: [+44 (0) 808 134 9852](tel:+4408081349852)
- France: [+33 (0) 8 00 90 76 20](tel:+330800907620)
- Germany: [+49 (0) 800 189 9396](tel:+4908001899396)
- Israel: [1-809-465-322](tel:1809465322)
- Singapore: [+65 800 852 3992](tel:+658008523992)