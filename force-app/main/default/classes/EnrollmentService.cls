public with sharing class EnrollmentService {

    public class EnrollmentRequest {
        public String firstName;
        public String lastName;
        public String email;
        public Id cohortId;
        public String externalId;
    }

    public class EnrollmentResult {
        public String externalId;
        public Id enrollmentId;
        public Boolean success = false;
        public String message;
    }

    public static List<EnrollmentResult> enroll(List<EnrollmentRequest> requests) {
        // 1. Collect keys
        Set<String> emails = new Set<String>();
        Set<Id> cohortIds = new Set<Id>();
        for (EnrollmentRequest r : requests) {
            emails.add(r.email.toLowerCase());
            cohortIds.add(r.cohortId);
        }

        // 2. Find existing learners (1 query) and create missing ones (1 DML)
        Map<String, Contact> learnerByEmail = new Map<String, Contact>();
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :emails WITH USER_MODE]) {
            learnerByEmail.put(c.Email.toLowerCase(), c);
        }
        List<Contact> newLearners = new List<Contact>();
        for (EnrollmentRequest r : requests) {
            String key = r.email.toLowerCase();
            if (!learnerByEmail.containsKey(key)) {
                Contact c = new Contact(FirstName = r.firstName, LastName = r.lastName, Email = key);
                learnerByEmail.put(key, c);   // same reference gets its Id after insert
                newLearners.add(c);
            }
        }
        insert as user newLearners;

        // 3. Capacity check (2 queries, any number of cohorts)
        Map<Id, Cohort__c> cohorts = new Map<Id, Cohort__c>(
            [SELECT Id, Capacity__c FROM Cohort__c WHERE Id IN :cohortIds WITH USER_MODE]);
        Map<Id, Integer> taken = EnrollmentSelector.seatsTaken(cohortIds);

        // 4. Build enrollments in memory
        List<EnrollmentResult> results = new List<EnrollmentResult>();
        List<EnrollmentResult> attempted = new List<EnrollmentResult>();
        List<Enrolment__c > toInsert = new List<Enrolment__c >();
        for (EnrollmentRequest r : requests) {
            EnrollmentResult res = new EnrollmentResult();
            res.externalId = r.externalId;
            results.add(res);

            Cohort__c cohort = cohorts.get(r.cohortId);
            Integer used = taken.containsKey(r.cohortId) ? taken.get(r.cohortId) : 0;
            if (cohort == null) { res.message = 'Cohort not found'; continue; }
            if (cohort.Capacity__c != null && used >= cohort.Capacity__c) { res.message = 'Cohort is full'; continue; }

            taken.put(r.cohortId, used + 1);
            toInsert.add(new Enrolment__c (
                Cohort__c = r.cohortId,
                Learner__c = learnerByEmail.get(r.email.toLowerCase()).Id,
                Status__c = 'Applied',
                External_Id__c = r.externalId));
            attempted.add(res);
        }

        // 5. Partial success: one bad row does not roll back the other 199
        Database.SaveResult[] saves = Database.insert(toInsert, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saves.size(); i++) {
            attempted[i].success = saves[i].isSuccess();
            attempted[i].enrollmentId = saves[i].getId();
            attempted[i].message = saves[i].isSuccess() ? 'Enrolled' : saves[i].getErrors()[0].getMessage();
        }
        return results;
    }

    public static void withdraw(Set<Id> enrollmentIds, String reason) {
        List<Enrolment__c > rows = [
            SELECT Id, Status__c FROM Enrolment__c 
            WHERE Id IN :enrollmentIds AND Status__c IN ('Applied', 'Enrolled')
            WITH USER_MODE
        ];
        for (Enrolment__c  e : rows) {
            e.Status__c = 'Withdrawn';
            e.Withdrawal_Reason__c = reason;
        }
        update as user rows;
    }

    public static Integer purgeWithdrawn(Integer daysOld) {
        Datetime cutoff = System.now().addDays(-daysOld);
        List<Enrolment__c> rows = [
            SELECT Id FROM Enrolment__c 
            WHERE Status__c = 'Withdrawn' AND LastModifiedDate < :cutoff
            WITH USER_MODE
        ];
        delete as user rows;
        return rows.size();
    }
}