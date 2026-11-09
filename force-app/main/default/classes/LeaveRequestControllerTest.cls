@isTest
private class LeaveRequestControllerTest {

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Tester', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
            UserName = alias + DateTime.now().getTime() + '@example.com');
        insert u;
        return u;
    }

    @isTest static void saveValid() {
        Leave_Request__c lr = LeaveRequestController.saveRequest(
            'Sick', Date.today(), Date.today().addDays(2), 'Fever');
        Leave_Request__c saved = [SELECT Duration__c, Status__c
                                  FROM Leave_Request__c WHERE Id = :lr.Id];
        System.assertEquals(3, saved.Duration__c);
        System.assertEquals('Pending', saved.Status__c);
    }

    @isTest static void saveInvalidDates() {
        Boolean thrown = false;
        try {
            LeaveRequestController.saveRequest(
                'Sick', Date.today(), Date.today().addDays(-1), 'x');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected an error for invalid dates');
    }

    @isTest static void saveMissingFields() {
        Boolean thrown = false;
        try {
            LeaveRequestController.saveRequest(null, null, null, 'x');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected an error for missing fields');
    }

    @isTest static void filterByStatus() {
        LeaveRequestController.saveRequest('Casual', Date.today(), Date.today(), 'Trip');
        System.assertEquals(1, LeaveRequestController.getRequests('Pending').size());
        System.assertEquals(0, LeaveRequestController.getRequests('Approved').size());
        System.assertEquals(1, LeaveRequestController.getRequests('All').size());
        System.assertEquals(1, LeaveRequestController.getRequests(null).size());
    }

    @isTest static void nonManagerCannotApprove() {
        Leave_Request__c lr = LeaveRequestController.saveRequest(
            'Earned', Date.today(), Date.today(), 'x');
        User u = createUser('nomgr');

        Boolean thrown = false;
        System.runAs(u) {
            System.assertEquals(false, LeaveRequestController.isManager());
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Approved', 'ok');
            } catch (AuraHandledException e) {
                thrown = true;
            }
        }
        System.assert(thrown, 'A non-manager should not be able to approve');
    }

    @isTest static void managerCanApproveAndReject() {
        User mgr;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            mgr = createUser('mgr');
            PermissionSet ps = new PermissionSet(
                Name = 'Test_Leave_Manager', Label = 'Test Leave Manager');
            insert ps;

            CustomPermission cp = [SELECT Id FROM CustomPermission
                                   WHERE DeveloperName = 'Leave_Manager' LIMIT 1];
            insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);

            insert new ObjectPermissions(
                ParentId = ps.Id, SobjectType = 'Leave_Request__c',
                PermissionsCreate = true, PermissionsRead = true, PermissionsEdit = true,
                PermissionsDelete = true,
                PermissionsViewAllRecords = true, PermissionsModifyAllRecords = true);

            insert new List<FieldPermissions>{
                new FieldPermissions(ParentId = ps.Id, SobjectType = 'Leave_Request__c',
                    Field = 'Leave_Request__c.Status__c',
                    PermissionsRead = true, PermissionsEdit = true),
                new FieldPermissions(ParentId = ps.Id, SobjectType = 'Leave_Request__c',
                    Field = 'Leave_Request__c.Manager_Comments__c',
                    PermissionsRead = true, PermissionsEdit = true)
            };

            insert new PermissionSetAssignment(AssigneeId = mgr.Id, PermissionSetId = ps.Id);
        }

        Leave_Request__c lr1 = LeaveRequestController.saveRequest(
            'Sick', Date.today(), Date.today(), 'a');
        Leave_Request__c lr2 = LeaveRequestController.saveRequest(
            'Casual', Date.today(), Date.today(), 'b');

        System.runAs(mgr) {
            System.assertEquals(true, LeaveRequestController.isManager());
            LeaveRequestController.updateStatus(lr1.Id, 'Approved', 'Enjoy');
            LeaveRequestController.updateStatus(lr2.Id, 'Rejected', 'Busy period');

            Boolean thrown = false;
            try {
                LeaveRequestController.updateStatus(lr1.Id, 'Bogus', 'x');
            } catch (AuraHandledException e) {
                thrown = true;
            }
            System.assert(thrown, 'Invalid status should be rejected');
        }

        System.assertEquals('Approved',
            [SELECT Status__c FROM Leave_Request__c WHERE Id = :lr1.Id].Status__c);
        System.assertEquals('Rejected',
            [SELECT Status__c FROM Leave_Request__c WHERE Id = :lr2.Id].Status__c);
        System.assertEquals('Busy period',
            [SELECT Manager_Comments__c FROM Leave_Request__c WHERE Id = :lr2.Id].Manager_Comments__c);
    }
}