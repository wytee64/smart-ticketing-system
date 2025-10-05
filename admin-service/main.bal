import ballerina/http;
import ballerina/log;
import ballerina/time;

// Types
type SalesReport record {|
    string reportId?;
    string reportType;
    string startDate;
    string endDate;
    int totalTickets;
    decimal totalRevenue;
    string generatedAt?;
|};

type TrafficReport record {|
    string reportId?;
    string routeId;
    string routeName;
    string period;
    int totalPassengers;
    int totalTrips;
    decimal averageOccupancy;
    string generatedAt?;
|};

SalesReport[] salesReports = [];
TrafficReport[] trafficReports = [];

service /admin on new http:Listener(9006) {

    resource function post reports/sales(@http:Payload json reportParams) returns json|error {
        string reportId = "RPT" + time:utcNow()[0].toString();

        SalesReport report = {
            reportId: reportId,
            reportType: "CUSTOM",
            startDate: check reportParams.startDate,
            endDate: check reportParams.endDate,
            totalTickets: 0,
            totalRevenue: 0.0,
            generatedAt: time:utcToString(time:utcNow())
        };

        salesReports.push(report);

        log:printInfo("Sales report generated: " + reportId);

        return report;
    }

    resource function post reports/traffic(@http:Payload json reportParams) returns json|error {
        string reportId = "TRPT" + time:utcNow()[0].toString();
        string routeId = check reportParams.routeId;

        http:Client transportClient = check new("http://transport-service:9002");
        json|error routeResponse = transportClient->get("/transport/routes/" + routeId);
        
        string routeName = "Unknown Route";
        if (routeResponse is json) {
            routeName = check routeResponse.routeName;
        }

        TrafficReport report = {
            reportId: reportId,
            routeId: routeId,
            routeName: routeName,
            period: check reportParams.period,
            totalPassengers: 0,
            totalTrips: 0,
            averageOccupancy: 0.0,
            generatedAt: time:utcToString(time:utcNow())
        };

        trafficReports.push(report);

        log:printInfo("Traffic report generated: " + reportId);

        return report;
    }

    resource function post disruptions(@http:Payload json disruption) returns json|error {
        log:printInfo("Service disruption published");

        return {
            "success": true,
            "message": "Service disruption published successfully"
        };
    }
    resource function get dashboard/stats() returns json|error {
        return {
            "totalPassengers": 0,
            "totalRoutes": 0,
            "activeTrips": 0,
            "todayTicketsSold": 0,
            "todayRevenue": 0.0,
            "timestamp": time:utcToString(time:utcNow())
        };
    }

    resource function get reports/sales() returns json|error {
        return {
            "reports": salesReports
        };
    }

    resource function get reports/traffic() returns json|error {
        return {
            "reports": trafficReports
        };
    }

    resource function get health() returns json {
        return {
            "service": "admin-service",
            "status": "UP",
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}