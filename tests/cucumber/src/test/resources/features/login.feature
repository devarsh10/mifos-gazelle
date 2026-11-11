@login @smoke
Feature: Login works for all 3 DPGs

  Scenario: MifosX login
    When I log in to MifosX tenant "greenbank" as "mifos" with password "password"
    Then the response status is 200
    And the response field "base64EncodedAuthenticationKey" is not empty

  Scenario: Payment Hub EE login
    When I log in to Payment Hub as "mifos" with password "password"
    Then the response status is 200
    And the response field "access_token" is not empty
    And the response field "token_type" is "Bearer"

  Scenario: vNext login
    When I log in to vNext as "admin" with password "superMegaPass"
    Then the response status is 200
    And the response field "access_token" is not empty
