pipeline {
    agent any
    options {
        // Bỏ qua checkout mặc định để tự dùng lệnh checkout với credential 
        skipDefaultCheckout(true)
    }
    environment {
        // Đặt tên registry Docker (Docker Hub user/orga)
        DOCKER_REGISTRY = "hoangvu42"
    }
    stages {
        stage('Checkout') {
            steps {
                // Checkout source từ GitHub dùng credential 'github-token'
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "${env.BRANCH_NAME}"]],
                    extensions: [[$class: 'LocalBranch']],  // checkout branch local
                    userRemoteConfigs: [[
                        url: "https://github.com/v4224/dacn.git",
                        credentialsId: "github-token"
                    ]]
                ])
            }
        }

        stage('Prepare Environment') {
            steps {
                script {
                    // Xác định BRANCH và IS_TAG, thiết lập IMAGE_TAG tương ứng
                    env.BRANCH = env.BRANCH_NAME ?: ''
                    env.IS_TAG = (env.BRANCH ==~ /^v\d+\.\d+\.\d+$/) ? "true" : "false"
                    // Lấy commit SHA ngắn (7 ký tự) để gắn tag nếu cần
                    def commitSha = sh(script: "git rev-parse --short=7 HEAD", returnStdout: true).trim()
                    if (env.BRANCH == "develop") {
                        env.IMAGE_TAG = "develop-${commitSha}"
                    } else if (env.IS_TAG == "true") {
                        env.IMAGE_TAG = "prod-${env.BRANCH}"
                    } else {
                        // Fallback cho nhánh khác (nếu có)
                        env.IMAGE_TAG = "${env.BRANCH}-${commitSha}"
                    }
                    echo "Running on branch/tag: ${env.BRANCH}, IS_TAG=${env.IS_TAG}, IMAGE_TAG=${env.IMAGE_TAG}"
                }
            }
        }

        stage('Detect Changed Services') {
            steps {
                script {
                    // 1. Dò các service thay đổi bằng git diff giữa HEAD và HEAD~1
                    def changedServices = []
                    try {
                        // Lấy danh sách file thay đổi
                        def diffOutput = sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim()
                        if (diffOutput) {
                            for (filePath in diffOutput.split("\n")) {
                                // Lấy tên thư mục đầu tiên làm tên service (giả sử mỗi service nằm ở root hoặc services/)
                                def topFolder = filePath.split('/')[0]
                                if (topFolder && !changedServices.contains(topFolder)) {
                                    changedServices.add(topFolder)
                                }
                            }
                        }
                    } catch (err) {
                        echo "git diff failed hoặc không có commit trước, sẽ build toàn bộ services."
                    }

                    // 2. Nếu không phát hiện thay đổi (changedServices rỗng), build tất cả service
                    if (changedServices.isEmpty()) {
                        echo "No changed services detected → build all services."
                        // Giả sử các thư mục service nằm thẳng dưới root (vd: api-gateway, identity-service, ...)
                        // Ta liệt kê tất cả các folder ở root, lọc ra những folder không phải là file hệ thống (Jenkinsfile, gitops, v.v.)
                        def allDirs = sh(
                            script: """
                                ls -1d */ 2>/dev/null || true
                            """,
                            returnStdout: true
                        ).trim()

                        // allDirs trả về dạng "api-gateway/\nidentity-service/\nprofile-service/..."
                        changedServices = []
                        for (dirName in allDirs.split("\n")) {
                            // loại bỏ ký tự slash cuối
                            def svc = dirName.replaceAll("/\$","")
                            // Bỏ qua thư mục không phải service (nếu bạn có thêm repo con như 'gitops', ignore nó ở đây)
                            if (svc && svc != "gitops" && svc != "changelogs") {
                                changedServices.add(svc)
                            }
                        }
                        echo "All services to build: ${changedServices.join(', ')}"
                    } else {
                        echo "Changed services detected: ${changedServices.join(', ')}"
                    }

                    // Lưu danh sách service thay đổi / toàn bộ service vào biến môi trường
                    env.CHANGED_SERVICES = changedServices.join(' ')
                }
            }
        }

        // (Bạn có thể mở lại phần SonarQube nếu cần)
        // stage('SonarQube Scan') {
        //     when {
        //         expression { env.BRANCH == "develop" }
        //     }
        //     steps {
        //         script {
        //             def services = env.CHANGED_SERVICES.split(' ')
        //             withSonarQubeEnv('SonarServer') {
        //                 for (svc in services) {
        //                     echo "Running SonarQube scan for service: ${svc}"
        //                     sh """
        //                         sonar-scanner \
        //                           -Dsonar.projectKey=${svc} \
        //                           -Dsonar.projectName=${svc} \
        //                           -Dsonar.sources=${svc} \
        //                           -Dsonar.java.binaries=${svc}/target/classes \
        //                           -Dsonar.host.url=$SONAR_HOST_URL \
        //                           -Dsonar.login=$SONAR_AUTH_TOKEN
        //                     """
        //                 }
        //             }
        //         }
        //     }
        // }

        stage('Build & Trivy Scan Images') {
            steps {
                script {
                    def services = env.CHANGED_SERVICES.split(' ')
                    for (svc in services) {
                        // Xác định tên image đầy đủ cho service
                        def imageName = "${env.DOCKER_REGISTRY}/${svc}:${env.IMAGE_TAG}"
                        echo "Building Docker image for ${svc}: ${imageName}"
                        sh "docker build -t ${imageName} ${svc}"
                        echo "Scanning image ${imageName} with Trivy"
                        // Quét lỗ hổng bảo mật bằng Trivy (HIGH, CRITICAL)
                        sh """
                            trivy image --exit-code 0 --severity HIGH,CRITICAL ${imageName} || true
                        """
                    }
                }
            }
        }

        stage('Push Docker Images') {
            steps {
                script {
                    // Đăng nhập Docker Hub sử dụng credential 'docker-hub'
                    withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"
                    }
                    def services = env.CHANGED_SERVICES.split(' ')
                    for (svc in services) {
                        def imageName = "${env.DOCKER_REGISTRY}/${svc}:${env.IMAGE_TAG}"
                        echo "Pushing image ${imageName}"
                        sh "docker push ${imageName}"
                    }
                }
            }
        }

        stage('Clone GitOps Repo') {
            steps {
                // Clone repository GitOps (chứa manifest môi trường) về thư mục 'gitops'
                dir('gitops') {
                    git url: 'https://github.com/v4224/dacn-gitops.git', credentialsId: 'github-token', branch: 'main'
                }
            }
        }

        stage('Update GitOps Config (Dev)') {
            when {
                branch 'develop'  // Chỉ chạy khi build nhánh develop
            }
            steps {
                dir('gitops') {
                    script {
                        def services = env.CHANGED_SERVICES.split(' ')
                        for (svc in services) {
                            echo "Updating image tag for service ${svc} in dev config"
                            sh """
                                # Thay thế dòng image trong các file dưới dev/ chứa tên service
                                sed -i "s#image: .*/${svc}:.*#image: ${env.DOCKER_REGISTRY}/${svc}:${env.IMAGE_TAG}#" dev/**/*.* || true
                            """
                        }
                        // Commit và push thay đổi (nếu có) với user jenkins-ci
                        def status = sh(script: "git status --porcelain", returnStdout: true).trim()
                        if (status) {
                            sh 'git config user.name "jenkins-ci"'
                            sh 'git config user.email "jenkins-ci@example.com"'
                            sh 'git commit -am "Update dev images to tag ${env.IMAGE_TAG}"'
                            sh 'git push'
                        } else {
                            echo "No changes in dev config to commit."
                        }
                    }
                }
            }
        }

        stage('Update GitOps Config (Prod & Changelog)') {
            when {
                expression { env.IS_TAG == "true" }  // Chỉ chạy khi build tag (production)
            }
            steps {
                dir('gitops') {
                    script {
                        def services = env.CHANGED_SERVICES.split(' ')
                        for (svc in services) {
                            echo "Updating image tag for service ${svc} in prod config"
                            sh """
                                sed -i "s#image: .*/${svc}:.*#image: ${env.DOCKER_REGISTRY}/${svc}:${env.IMAGE_TAG}#" prod/**/*.* || true
                            """
                        }
                        // Tạo file changelog cho release tag
                        def tagName = env.BRANCH  // Branch name in tag context is the tag
                        sh """
                            echo "# Release ${tagName}" > changelogs/release-${tagName}.md
                            echo "" >> changelogs/release-${tagName}.md
                            echo "Changelog for release ${tagName}." >> changelogs/release-${tagName}.md
                        """
                        sh "git add changelogs/release-${tagName}.md"
                        // Commit và push thay đổi cho prod config và changelog
                        def status = sh(script: "git status --porcelain", returnStdout: true).trim()
                        if (status) {
                            sh 'git config user.name "jenkins-ci"'
                            sh 'git config user.email "jenkins-ci@example.com"'
                            sh 'git commit -am "Release ${tagName}: update images and changelog"'
                            sh 'git push'
                        } else {
                            echo "No changes in prod config to commit."
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            slackSend(channel: '#release', color: 'good', message: "✅ Pipeline succeeded for *${env.BRANCH}* (IMAGE_TAG=${env.IMAGE_TAG})")
        }
        failure {
            slackSend(channel: '#release', color: 'danger', message: "❌ Pipeline failed for *${env.BRANCH}* (IMAGE_TAG=${env.IMAGE_TAG})")
        }
    }
}
