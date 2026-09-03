# ─────────────────────────────────────────────
# Backend Spring Boot — Multi-stage Dockerfile
# ─────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn clean package -DskipTests -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

# Variables de entorno requeridas en Digital Ocean:
# GEMINI_API_KEY, CORS_ALLOWED_ORIGINS, JWT_SECRET,
# SERVER_PORT (default 8087)
EXPOSE 8087
ENTRYPOINT ["java", "-jar", "app.jar"]
