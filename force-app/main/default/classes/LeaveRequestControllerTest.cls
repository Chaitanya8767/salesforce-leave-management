@isTest
private class LeaveRequestControllerTest {

    // ---------- helpers ----------

    private static Date inDays(Integer n) {
        return Date.today().addDays(n);
    }

    // Creates a Standard User and assigns the REAL deployed permission set
    // (Leave_Employee or Leave_Manager), so the tests exercise the same
    // object/field/custom-permission access that real users get.
    private static User createUser(String alias, String permSetName) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            u = new User(
                Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
                LastName = 'Tester', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                ProfileId = p.Id, TimeZoneSidKey = UserInfo.getTimeZone().getID(),
                UserName = alias + DateTime.now().getTime() + '@example.com');
            insert u;
            if (permSetName != null) {
                PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1];
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
        return u;
    }

    private static Leave_Request__c saveAs(User u, String type, Date s, Date e, String reason) {
        Leave_Request__c result;
        System.runAs(u) {
            result = LeaveRequestController.saveRequest(type, s, e, reason);
        }
        return result;
    }

    private static String statusOf(Id requestId) {
        return [SELECT Status__c FROM Leave_Request__c WHERE Id = :requestId].Status__c;
    }

    // ---------- applying for leave ----------

    @isTest static void saveValid() {
        User emp = createUser('emp1', 'Leave_Employee');
        Leave_Request__c lr = saveAs(emp, 'Sick', inDays(0), inDays(2), 'Fever');
        Leave_Request__c saved = [SELECT Duration__c, Status__c, Employee__c
                                  FROM Leave_Request__c WHERE Id = :lr.Id];
        System.assertEquals(3, saved.Duration__c);
        System.assertEquals('Pending', saved.Status__c);
        System.assertEquals(emp.Id, saved.Employee__c);
    }

    @isTest static void saveInvalidDates() {
        User emp = createUser('emp2', 'Leave_Employee');
        Boolean thrown = false;
        System.runAs(emp) {
            try {
                LeaveRequestController.saveRequest('Sick', inDays(0), inDays(-1), 'x');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('End date cannot be before start date'),
                    'Expected invalid date error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'Expected an error for invalid dates');
    }

    @isTest static void saveMissingFields() {
        User emp = createUser('emp3', 'Leave_Employee');
        Boolean thrown = false;
        System.runAs(emp) {
            try {
                LeaveRequestController.saveRequest(null, null, null, 'x');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('Please fill all required fields'),
                    'Expected missing fields error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'Expected an error for missing fields');
    }

    @isTest static void saveMissingReason() {
        User emp = createUser('emp4', 'Leave_Employee');
        Boolean thrown = false;
        System.runAs(emp) {
            try {
                LeaveRequestController.saveRequest('Sick', inDays(1), inDays(1), '  ');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('Please fill all required fields'),
                    'Expected missing reason error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'A blank reason should be rejected');
    }

    @isTest static void pastStartDateRejected() {
        User emp = createUser('emp5', 'Leave_Employee');
        Boolean thrown = false;
        System.runAs(emp) {
            try {
                LeaveRequestController.saveRequest('Casual', inDays(-3), inDays(-2), 'late entry');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('cannot be in the past'),
                    'Expected past date error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'A start date in the past should be rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Leave_Request__c]);
    }

    @isTest static void overlappingRequestRejected() {
        User emp = createUser('emp6', 'Leave_Employee');
        saveAs(emp, 'Sick', inDays(1), inDays(3), 'first');

        Boolean thrown = false;
        System.runAs(emp) {
            try {
                LeaveRequestController.saveRequest('Casual', inDays(3), inDays(5), 'overlaps day 3');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('overlaps'),
                    'Expected overlap error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'An overlapping request should be rejected');

        // A request on the next free day is fine.
        Leave_Request__c ok = saveAs(emp, 'Casual', inDays(4), inDays(4), 'next day');
        System.assertNotEquals(null, ok.Id);
    }

    // ---------- viewing requests ----------

    @isTest static void filterByStatus() {
        User emp = createUser('emp7', 'Leave_Employee');
        saveAs(emp, 'Casual', inDays(1), inDays(1), 'Trip');
        System.runAs(emp) {
            System.assertEquals(1, LeaveRequestController.getRequests('Pending').size());
            System.assertEquals(0, LeaveRequestController.getRequests('Approved').size());
            System.assertEquals(1, LeaveRequestController.getRequests('All').size());
            System.assertEquals(1, LeaveRequestController.getRequests(null).size());
        }
    }

    @isTest static void employeeSeesOnlyOwnRequests() {
        User emp1 = createUser('empA', 'Leave_Employee');
        User emp2 = createUser('empB', 'Leave_Employee');
        User mgr = createUser('mgrV', 'Leave_Manager');
        saveAs(emp1, 'Sick', inDays(1), inDays(1), 'a');
        saveAs(emp2, 'Sick', inDays(1), inDays(1), 'b');

        System.runAs(emp1) {
            System.assertEquals(1, LeaveRequestController.getRequests('All').size(),
                'Employee 1 must only see their own request');
        }
        System.runAs(emp2) {
            System.assertEquals(1, LeaveRequestController.getRequests('All').size(),
                'Employee 2 must only see their own request');
        }
        System.runAs(mgr) {
            System.assertEquals(2, LeaveRequestController.getRequests('All').size(),
                'Manager must see every request');
        }
    }

    // ---------- approval rules ----------

    @isTest static void nonManagerCannotApprove() {
        User emp = createUser('emp8', 'Leave_Employee');
        Leave_Request__c lr = saveAs(emp, 'Earned', inDays(1), inDays(1), 'x');

        Boolean thrown = false;
        System.runAs(emp) {
            System.assertEquals(false, LeaveRequestController.isManager());
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Approved', 'ok');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('Only managers'),
                    'Expected manager error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'A non-manager should not be able to approve');
        System.assertEquals('Pending', statusOf(lr.Id));
    }

    @isTest static void managerCanApproveAndReject() {
        User emp = createUser('emp9', 'Leave_Employee');
        User mgr = createUser('mgr1', 'Leave_Manager');

        Leave_Request__c lr1 = saveAs(emp, 'Sick', inDays(1), inDays(1), 'a');
        Leave_Request__c lr2 = saveAs(emp, 'Casual', inDays(5), inDays(5), 'b');

        System.runAs(mgr) {
            System.assertEquals(true, LeaveRequestController.isManager());
            LeaveRequestController.updateStatus(lr1.Id, 'Approved', 'Enjoy');
            LeaveRequestController.updateStatus(lr2.Id, 'Rejected', 'Busy period');
        }

        System.assertEquals('Approved', statusOf(lr1.Id));
        System.assertEquals('Rejected', statusOf(lr2.Id));
        System.assertEquals('Busy period',
            [SELECT Manager_Comments__c FROM Leave_Request__c WHERE Id = :lr2.Id].Manager_Comments__c);
    }

    @isTest static void invalidStatusRejected() {
        User emp = createUser('emp10', 'Leave_Employee');
        User mgr = createUser('mgr2', 'Leave_Manager');
        Leave_Request__c lr = saveAs(emp, 'Sick', inDays(1), inDays(1), 'test');

        Boolean thrown = false;
        System.runAs(mgr) {
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Bogus', 'x');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('Invalid status'),
                    'Expected Invalid status error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'Invalid status should be rejected');
        System.assertEquals('Pending', statusOf(lr.Id));
    }

    @isTest static void cannotDecideAlreadyDecidedRequest() {
        User emp = createUser('emp11', 'Leave_Employee');
        User mgr = createUser('mgr3', 'Leave_Manager');
        Leave_Request__c lr = saveAs(emp, 'Casual', inDays(1), inDays(1), 'trip');

        System.runAs(mgr) {
            LeaveRequestController.updateStatus(lr.Id, 'Approved', 'ok');
        }

        Boolean thrown = false;
        System.runAs(mgr) {
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Rejected', 'changed mind');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('Only Pending'),
                    'Expected Pending error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'Should not be able to decide an already-decided request');
        System.assertEquals('Approved', statusOf(lr.Id));
    }

    @isTest static void rejectWithoutCommentFails() {
        User emp = createUser('emp12', 'Leave_Employee');
        User mgr = createUser('mgr4', 'Leave_Manager');
        Leave_Request__c lr = saveAs(emp, 'Earned', inDays(1), inDays(1), 'personal');

        Boolean thrownNull = false;
        System.runAs(mgr) {
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Rejected', null);
            } catch (AuraHandledException e) {
                thrownNull = true;
                System.assert(e.getMessage().contains('comment is required'),
                    'Expected comment required error, got: ' + e.getMessage());
            }
        }
        System.assert(thrownNull, 'Rejecting with no comment should fail');

        Boolean thrownWhitespace = false;
        System.runAs(mgr) {
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Rejected', '   ');
            } catch (AuraHandledException e) {
                thrownWhitespace = true;
                System.assert(e.getMessage().contains('comment is required'),
                    'Expected comment required error, got: ' + e.getMessage());
            }
        }
        System.assert(thrownWhitespace, 'Rejecting with whitespace-only comment should fail');
        System.assertEquals('Pending', statusOf(lr.Id));
    }

    @isTest static void managerCannotDecideOwnRequest() {
        User mgr = createUser('mgr5', 'Leave_Manager');
        Leave_Request__c lr = saveAs(mgr, 'Casual', inDays(1), inDays(1), 'my own leave');

        Boolean thrown = false;
        System.runAs(mgr) {
            try {
                LeaveRequestController.updateStatus(lr.Id, 'Approved', 'self approve');
            } catch (AuraHandledException e) {
                thrown = true;
                System.assert(e.getMessage().contains('your own'),
                    'Expected self-approval error, got: ' + e.getMessage());
            }
        }
        System.assert(thrown, 'A manager must not approve their own request');
        System.assertEquals('Pending', statusOf(lr.Id));
    }

    @isTest static void aiSummaryManagerOnly() {
        User emp = createUser('emp14', 'Leave_Employee');
        User mgr = createUser('mgr6', 'Leave_Manager');
        Leave_Request__c lr = saveAs(emp, 'Sick', inDays(1), inDays(1), 'Fever');

        Boolean blocked = false;
        System.runAs(emp) {
            try {
                LeaveRequestController.getAiSummary(lr.Id);
            } catch (AuraHandledException e) {
                blocked = e.getMessage().contains('Only managers');
            }
        }
        System.assert(blocked, 'Employees must not generate AI summaries');

        // The Prompt Builder call cannot really run in a test, so a manager
        // gets either a summary or the friendly "unavailable" error.
        System.runAs(mgr) {
            try {
                System.assertNotEquals(null, LeaveRequestController.getAiSummary(lr.Id));
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('AI summary is unavailable'),
                    'Unexpected error: ' + e.getMessage());
            }
        }
    }
}
