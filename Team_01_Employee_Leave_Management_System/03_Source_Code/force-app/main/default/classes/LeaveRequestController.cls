public with sharing class LeaveRequestController {

    @AuraEnabled(cacheable=true)
    public static Boolean isManager() {
        return FeatureManagement.checkPermission('Leave_Manager');
    }

    @AuraEnabled
    public static Leave_Request__c saveRequest(String leaveType, Date startDate,
                                               Date endDate, String reason) {
        if (String.isBlank(leaveType) || startDate == null || endDate == null) {
            throw new AuraHandledException('Please fill all required fields.');
        }
        if (endDate < startDate) {
            throw new AuraHandledException('End date cannot be before start date.');
        }
        Leave_Request__c lr = new Leave_Request__c(
            Leave_Type__c = leaveType,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Duration__c = startDate.daysBetween(endDate) + 1,
            Reason__c = reason,
            Status__c = 'Pending',
            Employee__c = UserInfo.getUserId()
        );
        try {
            insert lr;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
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
            throw new AuraHandledException('Only managers can approve or reject requests.');
        }
        if (status != 'Approved' && status != 'Rejected') {
            throw new AuraHandledException('Invalid status.');
        }
        Leave_Request__c lr = new Leave_Request__c(
            Id = requestId,
            Status__c = status,
            Manager_Comments__c = comments
        );
        try {
            update lr;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}