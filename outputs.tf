# Configure kubectl access
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region us-west-2 --name ${aws_eks_cluster.eks.name}"
}
output "clustername" {
 value = aws_eks_cluster.eks.name
}
