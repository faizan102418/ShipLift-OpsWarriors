# Stage 1: Build application and create a minimal Java runtime
FROM maven:3.9-eclipse-temurin-21-alpine@sha256:308cba8b638ed7e4658cea3f8399066219466211c805f6d5728c3c9c7614661b AS builder

WORKDIR /app

COPY pom.xml ./
RUN mvn -B dependency:go-offline

COPY src/ ./src/
# Build application and generate the custom Java runtime
RUN mvn -B -DskipTests package \
    && jlink \
    --add-modules java.base,java.logging,java.management,java.naming,java.net.http,java.security.jgss,java.sql,java.xml,java.instrument,jdk.crypto.ec,jdk.unsupported,java.desktop,java.rmi,java.prefs \
    --strip-debug \
    --no-man-pages \
    --no-header-files \
    --compress=2 \
    --output /opt/custom-jre


# Stage 2: Minimal Alpine runtime
FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

WORKDIR /app

RUN apk upgrade --no-cache \
    && apk add --no-cache libstdc++=15.2.0-r5 ca-certificates=20261020-r0 \
    && addgroup -S -g 10001 app \
    && adduser -S -u 10001 -G app app

COPY --from=builder /opt/custom-jre /opt/custom-jre
COPY --from=builder --chown=app:app /app/target/order-service.jar ./app.jar

ENV PATH="/opt/custom-jre/bin:${PATH}"

USER app

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD ["sh", "-c", "wget -q -O /dev/null http://127.0.0.1:8082/health || exit 1"]

ENTRYPOINT ["java", "-jar", "app.jar"]
