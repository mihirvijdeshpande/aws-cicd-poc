properties([
        parameters([
            choice(name: 'AWS_ACCOUNT', defaultValue: 'dev', choices: 'dev\ntest\nprod'),
            choice(name: 'AWS_REGION', defaultValue: 'us-east-1', choices: 'us-east-1\neu-west-1'),
            string(name: 'EXTRA_PACKER_ARGS', defaultValue: '', description: 'Additional (optional) args passed to Packer..', )
        ])
   ])
pipeline {
	agent { label 'docker' }
	environment {
	    AWS_DEFAULT_REGION = "${params.AWS_REGION}"
	    PACKER_ANSIBLE_IMAGE = 'dockerhub.cisco.com/xse-docker/packer-ansible:1.1.3-2.4.2.0'
	    TF_IMAGE = 'hashicorp/terraform:0.11.1'
	    CREDS_ID = "aws-${params.AWS_ACCOUNT}-account"
	}
	stages {
    // Don't need explicit checkout stage due to Jenkins SCM config.
		stage('Build/Update VPC Environment') {
            agent {
                docker {
                    reuseNode true
                    image '$TF_IMAGE'
                    args "-e NO_PROXY"
                }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${CREDS_ID}", accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    ansiColor('xterm') {
                        sh """
                            cd terraform/vpc_create
                            terraform init -backend-config=../${AWS_ACCOUNT}-account.ini -input=false -reconfigure
                            terraform workspace new ${AWS_ACCOUNT}-cicd-poc || terraform workspace select ${AWS_ACCOUNT}-cicd-poc
                            AWS_PROFILE=${AWS_ACCOUNT} terraform apply -var region=${AWS_REGION} -var profile=${AWS_ACCOUNT} -auto-approve
                        """
                    }
                }
            }
        }
        stage('Build Plan for APP Deployment') {
            agent {
                docker {
                    reuseNode true
                    image '$TF_IMAGE'
                    args "-e NO_PROXY"
                }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${CREDS_ID}", accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    ansiColor('xterm') {
                        // SHOULD THIS EVER BE USED IN PROD: ENSURE TO OUTPUT PLAN TO FILE AND EXECUTE APPLY AGAINST FILE!!!
                        sh """
                            cd terraform/webserver_create
                            terraform init -backend-config=../${AWS_ACCOUNT}-account.ini -input=false -reconfigure
                            terraform workspace new ${AWS_ACCOUNT}-cicd-poc || terraform workspace select ${AWS_ACCOUNT}-cicd-poc
                            AWS_PROFILE=${AWS_ACCOUNT} terraform plan -var region=${AWS_REGION} -var profile=${AWS_ACCOUNT}
                        """
                    }
                }
            }
        }
        stage('App Deploy Approval Step') {
            steps {
                script {
                  timeout(time: 10, unit: 'MINUTES') {
                    input(id: "Approval Gate", message: "Build/Update APP?", ok: 'Deploy')
                  }
                }
            }
        }
        stage('Deploy APP') {
            agent {
                docker {
                    reuseNode true
                    image '$TF_IMAGE'
                    args "-e NO_PROXY"
                }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${CREDS_ID}", accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    ansiColor('xterm') {
                        sh """
                            cd terraform/webserver_create
                            terraform init -backend-config=../${AWS_ACCOUNT}-account.ini -input=false -reconfigure
                            terraform workspace new ${AWS_ACCOUNT}-cicd-poc || terraform workspace select ${AWS_ACCOUNT}-cicd-poc
                            AWS_PROFILE=${AWS_ACCOUNT} terraform apply -var region=${AWS_REGION} -var profile=${AWS_ACCOUNT} -auto-approve
                        """
                    }
                }
            }
        }
	  }
}
