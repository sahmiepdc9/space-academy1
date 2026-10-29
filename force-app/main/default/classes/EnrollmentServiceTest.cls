@IsTest
private class EnrollmentServiceTest {
  @TestSetup
  static void setup() {
    Program__c p = new Program__c(Name = 'Salesforce Developer');
    insert p;
    insert new List<Cohort__c>{
      new Cohort__c(Name = 'C12', Program__c = p.Id, Capacity__c = 250),
      new Cohort__c(Name = 'Pilot', Program__c = p.Id, Capacity__c = 1)
    };
  }

  static Id cohortId(String name) {
    return [SELECT Id FROM Cohort__c WHERE Name = :name LIMIT 1].Id;
  }

  static List<EnrollmentService.EnrollmentRequest> requests(
    Id cohort,
    Integer n
  ) {
    List<EnrollmentService.EnrollmentRequest> reqs = new List<EnrollmentService.EnrollmentRequest>();
    for (Integer i = 0; i < n; i++) {
      EnrollmentService.EnrollmentRequest r = new EnrollmentService.EnrollmentRequest();
      r.firstName = 'Learner';
      r.lastName = 'No' + i;
      r.email = 'learner' + i + '@space.test';
      r.cohortId = cohort;
      r.externalId = 'EXT-' + i;
      reqs.add(r);
    }
    return reqs;
  }

  @IsTest
  static void enrollsTwoHundredInOneTransaction() {
    Id c12 = cohortId('C12');
    Test.startTest();
    List<EnrollmentService.EnrollmentResult> results = EnrollmentService.enroll(
      requests(c12, 200)
    );
    Test.stopTest();

    Assert.areEqual(
      200,
      [SELECT COUNT() FROM Enrolment__c WHERE Cohort__c = :c12]
    );
    for (EnrollmentService.EnrollmentResult r : results) {
      Assert.isTrue(r.success, r.message);
    }
  }

  @IsTest
  static void rejectsWhenCohortIsFull() {
    List<EnrollmentService.EnrollmentResult> results = EnrollmentService.enroll(
      requests(cohortId('Pilot'), 2)
    );
    Assert.isTrue(results[0].success);
    Assert.isFalse(results[1].success);
    Assert.areEqual('Cohort is full', results[1].message);
  }

  @IsTest
  static void reusesExistingLearnerByEmail() {
    EnrollmentService.enroll(requests(cohortId('C12'), 1));
    List<EnrollmentService.EnrollmentRequest> again = requests(
      cohortId('Pilot'),
      1
    );
    again[0].externalId = 'EXT-PILOT-0';
    EnrollmentService.enroll(again);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Contact WHERE Email = 'learner0@space.test']
    );
  }

  @IsTest
  static void userModeBlocksUserWithoutAccess() {
    Profile minimal = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User u = new User(
      Alias = 'noaccs',
      Email = 'noaccess@novaridge.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoAccess',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = minimal.Id,
      TimeZoneSidKey = 'America/Toronto',
      UserName = 'noaccess' + DateTime.now().getTime() + '@novaridge.test'
    );
    insert u;

    Id c12 = cohortId('C12');
    Boolean blocked = false;
    System.runAs(u) {
      try {
        EnrollmentService.enroll(requests(c12, 1));
      } catch (Exception e) {
        blocked = true; // user mode enforced the missing object permissions
      }
    }
    Assert.isTrue(
      blocked,
      'A user with no object access must not be able to enroll'
    );
  }
}
