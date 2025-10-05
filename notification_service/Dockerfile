# Use a specific Ballerina image and allow cross-arch on Windows
FROM --platform=$BUILDPLATFORM ballerina/ballerina:2201.12.10

# Work in a folder we control
WORKDIR /workspace

# Use root so we never hit permission errors
USER root

# Copy project files
COPY . /workspace

# Ensure write perms and build the project
RUN mkdir -p /workspace/target \
    && chmod -R 777 /workspace \
    && bal build

# Expose the service port
EXPOSE 8086

# Run the service
CMD ["bal", "run"]
