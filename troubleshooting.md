# Báo Cáo Chẩn Đoán & Khắc Phục Sự Cố Pipeline CI/CD (Troubleshooting Report)

## 1. Bảng Tổng Hợp 3 Sự Cố Đứt Gãy Pipeline

| Mã Lỗi | Tên Sự Cố | Triệu Chứng / Log Lỗi | Nguyên Nhân Gốc Rễ | Giải Pháp Khắc Phục |
| :--- | :--- | :--- | :--- | :--- |
| **Lỗi 1** | **Permission Denied** | `/home/runner/work/_temp/...: ./gradlew: Permission denied` | Tệp `gradlew` không có cờ thực thi `+x` khi chạy trên runner Linux (`ubuntu-latest`). | Thêm lệnh `run: chmod +x gradlew` trước bước thực thi test. |
| **Lỗi 2** | **Authentication Failed** | `Error response from daemon: Get "https://ghcr.io/v2/": unauthorized` | Truyền sai tên biến Secret (sai chính tả hoặc sai định danh biến) trong `docker/login-action@v3`. | Chuẩn hóa chính xác tên biến Secret thành `${{ secrets.REGISTRY_TOKEN }}`. |
| **Lỗi 3** | **Build Context Error** | `failed to solve: failed to read dockerfile: open Dockerfile: no such file or directory` | Chỉ định sai thư mục ngữ cảnh (build context) hoặc sai đường dẫn tới tệp `Dockerfile`. | Cấu hình tường minh `context: .` và `file: ./Dockerfile` trong `docker/build-push-action@v5`. |

---

## 2. Phân Tích Chi Tiết & Hướng Khắc Phục Từng Lỗi

### 🔴 Lỗi 1: Permission Denied (Gradle Wrapper)

#### a. Log lỗi trên GitHub Actions Runner
```text
Run ./gradlew test
/home/runner/work/spring-boot-app/spring-boot-app/run.sh: line 1: ./gradlew: Permission denied
Error: Process completed with exit code 126.
```

#### b. Nguyên nhân gốc rễ (Root Cause)
- Khi mã nguồn được commit và push từ môi trường Windows (hệ thống tệp NTFS không quản lý thuộc tính bit thực thi POSIX `100755`), tệp script `gradlew` bị lưu trên Git index ở chế độ mặc định `100644` (không có quyền thực thi).
- Khi runner `ubuntu-latest` tải code về (`actions/checkout@v4`), `gradlew` thiếu quyền `execute`, dẫn đến lỗi hệ thống `Permission denied` (Exit code 126).

#### c. Giải pháp khắc phục
Thêm bước cấp quyền thực thi ngay trước khi gọi `./gradlew test`:
```diff
+     - name: Cấp quyền thực thi cho Gradle Wrapper
+       run: chmod +x gradlew

      - name: Chạy Unit Tests
        run: ./gradlew test
```

---

### 🔴 Lỗi 2: Authentication Failed (Đăng Nhập Docker Registry)

#### a. Log lỗi trên GitHub Actions Runner
```text
Run docker/login-action@v3
  with:
    registry: ghcr.io
    username: leducanh
    password: ***
Logging into ghcr.io...
Error: Username and password required
# Hoặc: Error response from daemon: Get "https://ghcr.io/v2/": unauthorized
Error: Process completed with exit code 1.
```

#### b. Nguyên nhân gốc rễ (Root Cause)
- Trong kịch bản workflow ban đầu, biến bí mật bị truyền sai cú pháp hoặc sai tên biến, ví dụ: `${{ secrets.REGISTY_TOKEN }}` (sai chính tả `REGISTY`), `${{ secrets.GITHUB_TOKEN }}` (không đủ quyền push package), hoặc `${{ secrets.DOCKER_PASSWORD }}`.
- Do biến rỗng hoặc sai giá trị xác thực, bước đăng nhập vào GitHub Container Registry (`ghcr.io`) bị từ chối truy cập (HTTP 401 Unauthorized).

#### c. Giải pháp khắc phục
Kiểm tra biến Secret đã lưu trong **Settings** -> **Secrets and variables** -> **Actions** là `REGISTRY_TOKEN`, sau đó chuẩn hóa lại kịch bản:
```diff
      - name: Đăng nhập vào GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
-         password: ${{ secrets.REGISTY_TOKEN }}   # Sai chính tả
+         password: ${{ secrets.REGISTRY_TOKEN }}  # Chuẩn xác
```

---

### 🔴 Lỗi 3: Build Context Error (Không Tìm Thấy Dockerfile)

#### a. Log lỗi trên GitHub Actions Runner
```text
Run docker/build-push-action@v5
#1 [internal] load local build context
#1 transferring context: 2B done
#1 ERROR: failed to solve: failed to read dockerfile: open /var/lib/docker/tmp/.../Dockerfile: no such file or directory
Error: buildx failed with: ERROR: failed to solve: failed to read dockerfile
Error: Process completed with exit code 1.
```

#### b. Nguyên nhân gốc rễ (Root Cause)
- Tham số `context` và `file` không được chỉ định hoặc trỏ sai thư mục làm việc (ví dụ: `context: ./app` hoặc không khai báo `file` khiến Docker Buildx tìm kiếm ở thư mục không tồn tại).
- Do không xác định được vị trí `Dockerfile` trong không gian làm việc của runner, tiến trình build Docker Image thất bại.

#### c. Giải pháp khắc phục
Chỉ định rõ ràng `context: .` (thư mục gốc workspace) và đường dẫn file cụ thể `file: ./Dockerfile`:
```diff
      - name: Build và Push Docker Image lên GHCR
        uses: docker/build-push-action@v5
        with:
-         context: ./wrong-path
+         context: .
+         file: ./Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/spring-boot-app:latest
```

---

## 3. Kịch Bản Workflow Sau Khi Khắc Phục Hoàn Chỉnh

Tệp kịch bản [broken-pipeline.yml](file:///e:/Admin/Documents/PTIT_CNTT2_IT209/PTIT_CNTT2_IT209_SS12/homework/session_12/ex5/.github/workflows/broken-pipeline.yml):

```yaml
name: CI/CD Pipeline - Fixed

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]
  workflow_dispatch:

jobs:
  test:
    name: Gradle Test & Build JAR
    runs-on: ubuntu-latest
    steps:
      - name: Checkout mã nguồn
        uses: actions/checkout@v4

      - name: Thiết lập môi trường JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
          cache: 'gradle'

      # Fix Lỗi 1: Cấp quyền thực thi cho Gradle Wrapper
      - name: Cấp quyền thực thi cho Gradle Wrapper
        run: chmod +x gradlew

      - name: Chạy Unit Tests
        run: ./gradlew test

      - name: Đóng gói ứng dụng JAR
        run: ./gradlew bootJar -x test

  docker-build:
    name: Build & Push Docker Image
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout mã nguồn
        uses: actions/checkout@v4

      - name: Thiết lập Docker Buildx
        uses: docker/setup-buildx-action@v3

      # Fix Lỗi 2: Đăng nhập Registry với biến Secret chính xác
      - name: Đăng nhập vào GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.REGISTRY_TOKEN }}

      # Fix Lỗi 3: Chỉ định rõ context và file Dockerfile
      - name: Build và Push Docker Image lên GHCR
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/spring-boot-app:latest
            ghcr.io/${{ github.repository_owner }}/spring-boot-app:${{ github.sha }}
```

---

## 4. Kết Quả Xác Minh Tích Xanh Trên GitHub Actions

Sau khi đẩy commit sửa lỗi lên nhánh `main`, toàn bộ 2 Job (`test` và `docker-build`) thực thi trơn tru và trả về kết quả **tích xanh 100%**:

![Kết quả toàn bộ pipeline tích xanh](./pipeline_success.png)
