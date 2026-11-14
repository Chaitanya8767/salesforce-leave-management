public with sharing class LeaveRequestController {

    private static AuraHandledException newAuraException(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isManager() {
        return FeatureManagement.checkPermission('Leave_Manager');
    }

    @AuraEnabled
    public static Leave_Request__c saveRequest(String leaveType, Date startDate,
                                               Date endDate, String reason) {
        if (String.isBlank(leaveType) || startDate == null || endDate == null
                || String.isBlank(reason)) {
            throw newAuraException('Please fill all required fields.');
        }
        if (endDate < startDate) {
            throw newAuraException('End date cannot be before start date.');
        }
        if (startDate < Date.today()) {
            throw newAuraException('Start date cannot be in the past.');
        }

        // Block overlapping leave for the same employee (Pending or Approved).
        Id employeeId = UserInfo.getUserId();
        Integer overlapping = [SELECT COUNT() FROM Leave_Request__c
                               WHERE Employee__c = :employeeId
                               AND Status__c IN ('Pending', 'Approved')
                               AND Start_Date__c <= :endDate
                               AND End_Date__c >= :startDate
                               WITH USER_MODE];
        if (overlapping > 0) {
            throw newAuraException('You already have a Pending or Approved leave request that overlaps these dates.');
        }

        Leave_Request__c lr = new Leave_Request__c(
            Leave_Type__c = leaveType,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Duration__c = startDate.daysBetween(endDate) + 1,
            Reason__c = reason,
            Status__c = 'Pending',
            Employee__c = employeeId
        );
        try {
            insert as user lr;
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
        return lr;
    }

    @AuraEnabled
    public static List<Leave_Request__c> getRequests(String status) {
        if (String.isBlank(status) || status == 'All') {
            return [SELECT Id, Name, Leave_Type__c, Start_Date__c, End_Date__c, Duration__c,
                           Reason__c, Status__c, Manager_Comments__c, Employee__r.Name
                    FROM Leave_Request__c
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC LIMIT 200];
        }
        return [SELECT Id, Name, Leave_Type__c, Start_Date__c, End_Date__c, Duration__c,
                       Reason__c, Status__c, Manager_Comments__c, Employee__r.Name
                FROM Leave_Request__c
                WHERE Status__c = :status
                WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT 200];
    }

    @AuraEnabled
    public static void updateStatus(Id requestId, String status, String comments) {
        if (!FeatureManagement.checkPermission('Leave_Manager')) {
            throw newAuraException('Only managers can approve or reject requests.');
        }
        if (status != 'Approved' && status != 'Rejected') {
            throw newAuraException('Invalid status.');
        }
        List<Leave_Request__c> records = [SELECT Id, Name, Status__c, Employee__c,
                                                 Start_Date__c, End_Date__c
                                          FROM Leave_Request__c
                                          WHERE Id = :requestId WITH USER_MODE LIMIT 1];
        if (records.isEmpty()) {
            throw newAuraException('Leave request not found.');
        }
        Leave_Request__c existing = records[0];
        if (existing.Status__c != 'Pending') {
            throw newAuraException('Only Pending requests can be approved or rejected.');
        }
        if (existing.Employee__c == UserInfo.getUserId()) {
            throw newAuraException('You cannot approve or reject your own leave request.');
        }
        if (status == 'Rejected' && String.isBlank(comments)) {
            throw newAuraException('A comment is required when rejecting a request.');
        }
        Leave_Request__c lr = new Leave_Request__c(
            Id = requestId,
            Status__c = status,
            Manager_Comments__c = comments
        );
        try {
            update as user lr;
        } catch (Exception e) {
            throw newAuraException(e.getMessage());
        }
        notifyEmployee(existing, status, comments);
    }

    // AI helper for managers: asks the Prompt Builder template
    // "Leave_Request_Summary" for a short, neutral summary of one request.
    // It only suggests text; the manager still approves or rejects.
    @AuraEnabled
    public static String getAiSummary(Id requestId) {
        if (!FeatureManagement.checkPermission('Leave_Manager')) {
            throw newAuraException('Only managers can generate summaries.');
        }
        List<Leave_Request__c> recs = [SELECT Id FROM Leave_Request__c
                                       WHERE Id = :requestId WITH USER_MODE LIMIT 1];
        if (recs.isEmpty()) {
            throw newAuraException('Leave request not found.');
        }
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.isPreview = false;

            ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
            wv.value = new Map<String, String>{ 'id' => requestId };
            input.inputParams = new Map<String, ConnectApi.WrappedValue>{
                'Input:LeaveRequest' => wv
            };
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    'Leave_Request_Summary', input);
            return result.generations[0].text;
        } catch (Exception e) {
            throw newAuraException('AI summary is unavailable: ' + e.getMessage());
        }
    }

    // Tells the employee about the decision: bell (in-app) notification + e-mail.
    // Failures here must never undo the manager's decision, so they are only logged.
    private static void notifyEmployee(Leave_Request__c req, String status, String comments) {
        String title = 'Leave request ' + req.Name + ' ' + status.toLowerCase();
        String body = 'Your leave request ' + req.Name + ' ('
            + req.Start_Date__c.format() + ' to ' + req.End_Date__c.format()
            + ') was ' + status.toLowerCase() + '.'
            + (String.isBlank(comments) ? '' : ' Manager comment: ' + comments);

        try {
            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType
                                                  WHERE DeveloperName = 'Leave_Decision' LIMIT 1];
            if (!types.isEmpty()) {
                Messaging.CustomNotification note = new Messaging.CustomNotification();
                note.setNotificationTypeId(types[0].Id);
                note.setTitle(title);
                note.setBody(body);
                note.setTargetId(req.Id);
                note.send(new Set<String>{ String.valueOf(req.Employee__c) });
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Bell notification failed: ' + e.getMessage());
        }

        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(req.Employee__c);
            mail.setSaveAsActivity(false);
            mail.setSubject(title);
            mail.setPlainTextBody(body);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'E-mail notification failed: ' + e.getMessage());
        }
    }
}
