public with sharing class EnrollmentSelector {
  public static List<Cohort__c> rosterFor(Set<Id> cohortIds) {
    return [
      SELECT
        Id,
        Name,
        Capacity__c,
        Program__r.Name,
        (
          SELECT Id, Status__c, Learner__r.Name, Learner__r.Email
          FROM Enrollments__r
          ORDER BY Learner__r.LastName
        )
      FROM Cohort__c
      WHERE Id IN :cohortIds
      WITH USER_MODE
    ];
  }

  /** Seats taken = Applied + Enrolled, per cohort. One query for any number of cohorts. */
  public static Map<Id, Integer> seatsTaken(Set<Id> cohortIds) {
    Map<Id, Integer> taken = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Cohort__c cohortId, COUNT(Id) total
      FROM Enrolment__c
      WHERE Cohort__c IN :cohortIds AND Status__c IN ('Applied', 'Enrolled')
      WITH USER_MODE
      GROUP BY Cohort__c
    ]) {
      taken.put((Id) ar.get('cohortId'), (Integer) ar.get('total'));
    }
    return taken;
  }
}