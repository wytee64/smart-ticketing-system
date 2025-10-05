import ballerina/http;
import ballerina/time;

type Notification record {|
    string id?;
    string userId;
    string 'type?;        // escape keyword
    string title?;
    string message;
    string createdAt?;
    boolean read = false;
|};

final map<Notification[]> store = {}; // userId -> notifications[]

service / on new http:Listener(8086) {

    // Health: GET /health
    resource function get health() returns json {
        return { status: "up" };
    }

    // Create: POST /notify/test   (body: Notification)
    resource function post notify/test(Notification n) returns json {
        // Use the value method toString() instead of time:toString(...)
        n.createdAt = time:utcNow().toString();

        // Map lookup returns Notification[]? -> default to []
        Notification[] list = store[n.userId] ?: [];
        list.push(n);
        store[n.userId] = list;

        return { status: "stored", count: list.length() };
    }

    // Read: GET /notifications?userId=...
    resource function get notifications(string userId) returns Notification[] {
        // Optional -> default to []
        return store[userId] ?: [];
    }
}
