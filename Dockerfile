# Multi-stage build tối ưu kích thước cho Spring Boot
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Sao chép file JAR đã build
COPY build/libs/*.jar app.jar

# Khai báo cổng ứng dụng
EXPOSE 8080

# Chạy ứng dụng Spring Boot
ENTRYPOINT ["java", "-jar", "app.jar"]
