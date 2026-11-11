package org.mifos.gazelle.cucumber;

import io.cucumber.java.en.Then;
import io.cucumber.java.en.When;
import io.restassured.http.ContentType;
import io.restassured.response.Response;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.emptyOrNullString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;

public class LoginSteps {

    private Response response;

    private String domain() {
        String domain = System.getenv("GAZELLE_DOMAIN");
        return (domain == null || domain.isBlank()) ? "mifos.gazelle.test" : domain;
    }

    @When("I log in to MifosX tenant {string} as {string} with password {string}")
    public void logInToMifosX(String tenant, String username, String password) {
        String body = String.format("{\"username\":\"%s\",\"password\":\"%s\"}", username, password);
        response = given()
                .relaxedHTTPSValidation()
                .header("Fineract-Platform-TenantId", tenant)
                .contentType(ContentType.JSON)
                .body(body)
                .post("http://mifos." + domain() + "/fineract-provider/api/v1/authentication");
    }

    @When("I log in to Payment Hub as {string} with password {string}")
    public void logInToPaymentHub(String username, String password) {
        response = given()
                .relaxedHTTPSValidation()
                .contentType(ContentType.URLENC)
                .formParam("grant_type", "password")
                .formParam("client_id", "opsapp")
                .formParam("username", username)
                .formParam("password", password)
                .post("https://keycloak-ops." + domain() + "/realms/paymenthub/protocol/openid-connect/token");
    }

    @When("I log in to vNext as {string} with password {string}")
    public void logInToVNext(String username, String password) {
        String body = String.format(
                "{\"grant_type\":\"password\",\"client_id\":\"security-bc-ui\",\"username\":\"%s\",\"password\":\"%s\"}",
                username, password);
        response = given()
                .relaxedHTTPSValidation()
                .contentType(ContentType.JSON)
                .body(body)
                .post("https://vnextadmin." + domain() + "/auth_n/token");
    }

    @Then("the response status is {int}")
    public void theResponseStatusIs(int expected) {
        response.then().log().ifValidationFails().statusCode(expected);
    }

    @Then("the response field {string} is not empty")
    public void theResponseFieldIsNotEmpty(String field) {
        response.then().log().ifValidationFails().body(field, not(emptyOrNullString()));
    }

    @Then("the response field {string} is {string}")
    public void theResponseFieldIs(String field, String expected) {
        response.then().log().ifValidationFails().body(field, equalTo(expected));
    }
}
