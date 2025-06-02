pipeline {
  agent { label 'jenkins' }

  environment {
    REGISTRY_CRED    = credentials('docker-hub')
    IMAGE_REGISTRY   = "hoangvu42"
    SONARQUBE_ENV    = "sonarqube-server"
    GITOPS_REPO_URL  = "https://github.com/v4224/dacn-gitops.git"
    ALL_SERVICES     = "api-gateway,identity-service,profile-service,notification-service,post-service"
  }

  options {
    skipDefaultCheckout(true)
    timestamps()
  }

  stages {
    // ==========================
    // 1. VALIDATE RUN CONTEXT
    //    - Phải là:
    //      * commit trên develop
    //      * PR/MR (changeRequest) vào develop
    //      * hoặc tag mới có pattern “v*” (giả định tạo từ deploy)
    // ==========================
    stage('Validate Run Context') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        echo "✅ Pipeline được phép chạy: commit/PR trên develop hoặc tag mới từ deploy"
      }
    }

    // ==========================
    // 2. CHECKOUT SOURCE
    //    - Chỉ chạy trên develop/PR hoặc tag
    //    - Nếu GIT_BRANCH bắt đầu bằng "refs/tags/", gán TAG_NAME và BRANCH='deploy'
    //    - Ngược lại, BRANCH=BRANCH_NAME
    // ==========================
    stage('Checkout Source') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        checkout scm

        script {
          def rawBranch = env.GIT_BRANCH
          echo "GIT_BRANCH = ${rawBranch}"

          if (rawBranch?.startsWith("refs/tags/")) {
            // Build tag
            env.TAG_NAME = rawBranch.replace("refs/tags/", "")
            // Giả định tag chỉ tạo từ branch deploy
            env.BRANCH = "deploy"
            echo "→ Detected a tag build: ${env.TAG_NAME} (gán BRANCH=deploy)"
          } else {
            // Build nhánh hoặc PR
            env.TAG_NAME = ""
            // Nếu là PR, BRANCH_NAME sẽ như "PR-xx"; vẫn set BRANCH=develop để chạy logic giống develop
            env.BRANCH = (changeRequest() ? "develop" : env.BRANCH_NAME)
            echo "→ Detected a branch/PR build: ${env.BRANCH_NAME} → gán BRANCH=${env.BRANCH}"
          }
        }
      }
    }

    // ==========================
    // 3. SET IMAGE TAG
    //    - Nếu BRANCH=='deploy' (tag build), gán prod-<TAG> hoặc prod-<BUILD_ID>
    //    - Nếu BRANCH=='develop' (commit/PR), gán <branch>-<shortSHA>
    // ==========================
    stage('Set Image Tag') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        script {
          def branch = env.BRANCH ?: "develop"
          if (branch == 'deploy') {
            // Build production (từ tag)
            env.IMAGE_TAG = "prod-${env.TAG_NAME ?: env.BUILD_ID}"
            env.RUN_SONAR  = "false"
          } else {
            // Develop (commit hoặc PR)
            def commitHash = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
            env.IMAGE_TAG = "${branch}-${commitHash}"
            env.RUN_SONAR  = "true"
          }
          echo "Image tag = ${env.IMAGE_TAG}"
          echo "Run SonarQube? => ${env.RUN_SONAR}"
        }
      }
    }

    // ==========================
    // 4. DETECT CHANGED SERVICES
    //    - Nếu BRANCH=='deploy' (tag), build tất cả
    //    - Nếu BRANCH=='develop' (commit/PR), so sánh diff với origin/develop
    // ==========================
    stage('Detect Changed Services') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        script {
          def all = ALL_SERVICES.split(',')
          if (env.BRANCH == 'deploy') {
            env.CHANGED_SERVICES = all.join(',')
            echo "→ BRANCH=deploy → build tất cả service"
          } else {
            // So sánh với origin/develop
            sh "git fetch origin develop"
            def diffRaw = sh(returnStdout: true, script: "git diff --name-only origin/develop").trim()
            if (diffRaw) {
              def changedDirs = diffRaw.split('\n').collect { it.split('/')[0] }.unique()
              def intersect = changedDirs.intersect(all as List)
              if (intersect.size() > 0) {
                env.CHANGED_SERVICES = intersect.join(',')
                echo "→ Các service có thay đổi: ${env.CHANGED_SERVICES}"
              } else {
                echo "→ Không có thay đổi trong service folders → build all"
                env.CHANGED_SERVICES = all.join(',')
              }
            } else {
              echo "→ Không có file nào thay đổi so với origin/develop → build all"
              env.CHANGED_SERVICES = all.join(',')
            }
          }
          echo "Danh sách service cần build: ${env.CHANGED_SERVICES}"
        }
      }
    }

    // ==========================
    // 5. SONARQUBE ANALYSIS
    //    - Chỉ chạy khi RUN_SONAR=='true' (tức trên develop, commit/PR)
    // ==========================
    stage('SonarQube Analysis') {
      when {
        allOf {
          expression { return env.RUN_SONAR == 'true' }
          expression { return env.CHANGED_SERVICES?.trim() }
        }
      }
      steps {
        script {
          def scannerHome = tool 'SonarScanner'
          def services = env.CHANGED_SERVICES.split(',')
          def sonarTasks = [:]
          services.each { svc ->
            sonarTasks[svc] = {
              dir(svc) {
                withSonarQubeEnv("${SONARQUBE_ENV}") {
                  sh "${scannerHome}/bin/sonar-scanner \
                      -Dsonar.projectKey=${svc} \
                      -Dsonar.sources=. \
                      -Dsonar.java.binaries=."
                }
              }
            }
          }
          parallel sonarTasks
        }
      }
      post {
        success {
          script {
            timeout(time: 15, unit: 'MINUTES') {
              waitForQualityGate(abortPipeline: true)
            }
          }
        }
        failure {
          echo "⚠️ SonarQube Analysis lỗi hoặc Quality Gate fail."
        }
      }
    }

    // ==========================
    // 6. BUILD & SCAN DOCKER IMAGES
    //    - Chạy trên develop (commit/PR) và trên deploy (tag)
    // ==========================
    stage('Build & Scan Docker Images') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        script {
          sh "echo ${REGISTRY_CRED_PSW} | docker login -u ${REGISTRY_CRED_USR} --password-stdin"

          sh """
            mkdir -p ${env.WORKSPACE}/.trivy-cache
            mkdir -p ${env.WORKSPACE}/trivy-reports
          """

          def services = env.CHANGED_SERVICES.split(',')
          def buildTasks = [:]
          services.each { svc ->
            buildTasks[svc] = {
              dir(svc) {
                sh "docker build -t ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG} ."
                sh """
                  docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v ${env.WORKSPACE}/.trivy-cache:/root/.cache/trivy \
                    -v ${env.WORKSPACE}/trivy-reports:/reports \
                    aquasec/trivy image \
                      --cache-dir /root/.cache/trivy \
                      --scanners vuln \
                      --timeout 15m \
                      --format template \
                      --template @contrib/html.tpl \
                      --output /reports/${svc}-trivy-scan-report.html \
                      ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG} || true
                """
                echo "→ Trivy scan xong cho ${svc}"
              }
            }
          }
          parallel buildTasks
        }
      }
    }

    // ==========================
    // 7. PUSH IMAGES
    // ==========================
    stage('Push Images') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        script {
          def services = env.CHANGED_SERVICES.split(',')
          def pushTasks = [:]
          services.each { svc ->
            pushTasks[svc] = {
              sh "docker push ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG}"
            }
          }
          parallel pushTasks
        }
      }
    }

    // ==========================
    // 8. UPDATE GITOPS MANIFESTS
    // ==========================
    stage('Update GitOps Manifests') {
      when {
        anyOf {
          branch 'develop'
          changeRequest()
          tag pattern: "v.*", comparator: "REGEXP"
        }
      }
      steps {
        script {
          def targetBranch = (env.BRANCH == 'deploy') ? 'product' : env.BRANCH
          withCredentials([usernamePassword(
              credentialsId: 'github-token',
              usernameVariable: 'GIT_USER',
              passwordVariable: 'GIT_PASS'
          )]) {
            if (fileExists('gitops')) {
              sh 'rm -rf gitops'
            }
            sh "git clone https://${GIT_USER}:${GIT_PASS}@github.com/v4224/dacn-gitops.git gitops"

            dir('gitops') {
              def exists = sh(returnStdout: true,
                              script: "git ls-remote --heads origin ${targetBranch} || true").trim()
              if (!exists) {
                sh "git checkout -b ${targetBranch}"
              } else {
                sh "git checkout ${targetBranch}"
              }

              def pathPrefix = (env.BRANCH == 'deploy') ? 'prod' : 'dev'
              def services = env.CHANGED_SERVICES.split(',')
              services.each { svc ->
                def file = "${pathPrefix}/${svc}/${svc}-deployment.yaml"
                sh """
                  sed -i 's#image: .*/${svc}:.*#image: ${IMAGE_REGISTRY}/${svc}:${env.IMAGE_TAG}#' ${file}
                """
              }
              sh 'git config user.name "jenkins-ci"'
              sh 'git config user.email "[email protected]"'
              sh 'git add .'
              sh "git commit -m 'Update image tags to ${env.IMAGE_TAG} [ci skip]' || echo 'No changes to commit'"
              sh "git push https://${GIT_USER}:${GIT_PASS}@github.com/v4224/dacn-gitops.git ${targetBranch}:${targetBranch}"
            }
          }
        }
      }
    }

    // ==========================
    // 9. GENERATE CHANGELOG (chỉ khi tag từ deploy)
    // ==========================
    stage('Generate Changelog (for prod)') {
      when {
        expression {
          return (env.TAG_NAME?.trim() && env.BRANCH == 'deploy')
        }
      }
      steps {
        script {
          echo "→ Generating changelog cho tag: ${env.TAG_NAME}"

          def prevTag = sh(returnStdout: true,
                          script: "git describe --tags --abbrev=0 \$(git rev-list --tags --skip=1 --max-count=1)").trim()
          echo "Previous tag = ${prevTag}"

          def changelog = sh(returnStdout: true,
                            script: "git log ${prevTag}..${env.TAG_NAME} --pretty=format:'- %s'").trim()
          def changelogFile = "gitops/changelogs/release-${env.TAG_NAME}.md"
          writeFile file: changelogFile, text: changelog

          dir('gitops') {
            sh 'git add changelogs/'
            sh "git commit -m 'Add changelog for ${env.TAG_NAME}' || echo 'No changelog changes to commit'"
            sh "git push origin ${env.BRANCH}"
          }
        }
      }
    }
  }

  post {
    success {
      script {
        if (env.BRANCH == 'deploy') {
          slackSend(channel: '#release', message: "✅ Version ${env.IMAGE_TAG} đã deploy thành công lên production.")
        }
      }
    }
    failure {
      script {
        if (env.BRANCH == 'deploy') {
          slackSend(channel: '#release', message: "❌ Deploy version ${env.IMAGE_TAG} thất bại.")
        }
      }
    }
  }
}
