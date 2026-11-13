# Employee Leave Management System (Salesforce & LWC)

**Wipro Salesforce Training Program – Phase II Mini Project (2026–27)**  
**Team Members:**  
- Chaitanya Walunjkar (Roll No: 25TC162)  
- Harshwardhan Kharat (Roll No: 25TC131)  
**Institution:** Dnyaan Prasad Global University – School of Technology and Research  

---

## 📌 Project Overview
The **Employee Leave Management System** is a full-stack Salesforce application built to streamline leave applications, manager approvals, real-time tracking, and automated validation. It eliminates manual email-based leave tracking by providing dedicated role-based interfaces for employees and managers.

---

## 🚀 Key Features
- **Leave Application Form (LWC):** Employees submit leave with a live duration calculation. Validation: all fields required, end date not before start date, **start date not in the past** (checked in the browser and again in Apex).
- **Leave Request List & Filtering (LWC):** Status filter (`All`, `Pending`, `Approved`, `Rejected`), live text search, loading and error states. It **refreshes automatically** (Lightning Message Service) when a request is submitted or decided.
- **Manager Approval Panel (LWC):** Visible only to users with the `Leave_Manager` custom permission. Approve or reject with comments (a comment is mandatory for rejection).
- **Notifications:** when a manager decides a request, the employee gets an **in-app (bell) notification** (`Leave_Decision` custom notification type) and an **e-mail**.
- **Server-Side Rules (Apex):**
  - `WITH USER_MODE` queries and `insert/update as user` enforce object and field security.
  - Rejects overlapping Pending/Approved requests for the same employee.
  - Only `Pending` requests can be decided; invalid statuses are refused.
  - A manager cannot approve or reject their own request.
- **Privacy:** `Leave_Request__c` is **Private** – employees see only their own requests; managers see all through the `Leave_Manager` permission set.

---

## 🛠️ Architecture & Tech Stack
- **Platform:** Salesforce Lightning Platform
- **UI:** Lightning Web Components (LWC), SLDS, Lightning Message Service
- **Backend:** Apex (`LeaveRequestController`, `LeaveRequestControllerTest`)
- **Data Model:** Custom object `Leave_Request__c` (leave type, dates, duration, reason, status, manager comments, employee lookup)
- **Security:** Custom Permission `Leave_Manager`, Permission Sets `Leave_Employee` and `Leave_Manager` (also grant the app and tab)
- **Tests:** 14 Apex test methods (run as users holding the real permission sets) and Jest tests for all three components.

---

## 📦 Deployment Instructions

### 1. Authorize Your Salesforce Org
```bash
sf org login web -a LeaveOrg
```

### 2. Deploy Metadata
```bash
sf project deploy start --target-org LeaveOrg
```

### 3. Assign Permission Sets
- **For Standard Employees:**
  ```bash
  sf org assign permset --name Leave_Employee --target-org LeaveOrg
  ```
- **For Managers:**
  ```bash
  sf org assign permset --name Leave_Manager --target-org LeaveOrg
  ```

### 4. Run Apex Unit Tests
(Notifications: e-mail needs *Setup → Deliverability → Access level = All email*. The bell notification works without it.)

```bash
sf apex run test --class-names LeaveRequestControllerTest --code-coverage --result-format human --wait 10 --target-org LeaveOrg
```

---

## 📁 Repository Structure
```
force-app/main/default/
├── classes/
│   ├── LeaveRequestController.cls          # Server-side controller & validation logic
│   ├── LeaveRequestController.cls-meta.xml
│   ├── LeaveRequestControllerTest.cls      # Test suite (14 test methods)
│   └── LeaveRequestControllerTest.cls-meta.xml
├── customPermissions/
│   └── Leave_Manager.customPermission-meta.xml
├── tabs/ messageChannels/ notificationtypes/   # app tab, refresh channel, bell notification type
├── permissionsets/
│   ├── Leave_Employee.permissionset-meta.xml
│   └── Leave_Manager.permissionset-meta.xml
├── objects/
│   └── Leave_Request__c/                   # Custom fields & object definition
└── lwc/
    ├── leaveRequestForm/                   # Leave application component
    ├── leaveRequestList/                   # Request tracking & filtering component
    └── leaveApproval/                      # Manager approval/rejection panel
```
