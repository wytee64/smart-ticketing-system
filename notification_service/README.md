# Smart Ticketing System — Person 6
## Docker Compose Testing + Notification Service

### Implemented By
**Name:** Leane Tafadzwa Kwidini  
**Role:** Person 6 — Docker Compose Integration + Notification Service  

---

## Overview
This component implements the **Notification Service** for the Smart Ticketing System project.  
It is responsible for sending and retrieving notifications related to trip disruptions and ticket updates.

The service is containerized using **Docker** and integrated with the group’s microservices through **Docker Compose**, enabling multi-container communication and testing.

---

## Service Description
**Notification Service**
- Handles POST requests to store notifications for users.
- Handles GET requests to fetch notifications by user ID.
- Each notification includes:
  - `userId`
  - `message`
  - `createdAt` timestamp

---

## docker Setup

### Build Docker Image
From the project root (`DSA_assignment2`):

```bash
docker build -t notification-service ./notification_service
