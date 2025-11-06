# PC Monitoring Dashboard (PowerShell → n8n → SQL → React)

This project is a full telemetry pipeline for monitoring a Windows PC in real time using **PowerShell**, **n8n**, **SQL DataTables**, and a **React dashboard**. The system captures local system metrics, stores them in n8n, and exposes an API that the React frontend uses to display the latest recorded data.

---

## Overview

**Architecture:**
```
PowerShell → n8n Webhook → SQL DataTable → n8n API Workflow → React Dashboard
```

The PowerShell client collects system data periodically and sends it to n8n. n8n stores every record in a SQL DataTable. A second n8n workflow acts as an API, returning the latest telemetry snapshot to the React dashboard.

Live Demo:
**https://v0-dashboard-with-json-data-two.vercel.app/**

---

## Features
- Real-time PC telemetry ingestion
- PowerShell script captures CPU, RAM, OS info, network, active window, etc.
- Clean data processing and normalization inside n8n
- SQL DataTable storage for historical indexing
- API endpoint that always returns the latest record
- React dashboard for real-time visualization

---

## System Components

### 1. PowerShell Telemetry Client
The `send info.ps1` script collects:
- Machine name, user name
- OS info: caption, version, build, architecture
- CPU load, logical processors
- RAM total/free/used and percentage
- Active window title and process
- Network adapters, IPv4, WiFi SSID
- Data/time of collection

It sends the JSON payload to the ingestion webhook:
```
POST https://n8n.srv1034252.hstgr.cloud/webhook/079ca5a3-ceac-41d9-bdb7-a59f114a89f4
```

### 2. n8n Workflow: Ingest & Store
Workflow steps:
1. **Webhook** receives JSON from PowerShell.
2. **Code (Data order)** cleans, decodes, and restructures payload.
3. **Insert Row** writes the data into a SQL DataTable.
4. **Respond to Webhook** returns OK.

This workflow acts as the storage backend.

### 3. n8n Workflow: API
This workflow exposes a public endpoint for the server/frontend.

Steps:
1. **Webhook** receives a request from React.
2. **Get row(s)** queries the SQL table.
3. **Merge** consolidates data rows.
4. **Último** sorts by ID and timestamp to extract the most recent entry.
5. **Respond to Webhook** outputs a clean JSON.

This provides a simple REST-like API for the dashboard.

API Endpoint:
```
GET https://n8n.srv1034252.hstgr.cloud/webhook/ff454afd-eb30-4d2e-ab13-54c945981f0a
```

### 4. React Dashboard
The dashboard fetches the API and displays:
- CPU metrics
- RAM usage
- Active application
- Network status and SSID
- IP info
- OS details
- Machine metadata
- Last capture time

It visualizes **the latest available telemetry in real time**.

Demo:
https://v0-dashboard-with-json-data-two.vercel.app/

---

## Usage
1. Run the PowerShell script on your Windows PC.
2. Telemetry is automatically ingested by n8n.
3. The dashboard retrieves the latest snapshot via API.
4. View system metrics in real time.

---

## License
This project is provided for **personal and non-commercial use only**. Commercial use, resale, or redistribution is not permitted.

---

## Author
Developed by OXSR.
