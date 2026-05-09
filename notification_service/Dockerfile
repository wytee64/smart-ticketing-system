                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 # Use Ballerina runtime image with multi-platform support
FROM --platform=$BUILDPLATFORM ballerina/ballerina:2201.12.10

# Set working directory
WORKDIR /app

# Copy Ballerina project files
COPY . .

# Build the Ballerina application
USER root
RUN bal build
USER ballerina

# Expose port
EXPOSE 8085

# Run the application using the built JAR
CMD ["bal", "run", "target/bin/notification_service.jar"]