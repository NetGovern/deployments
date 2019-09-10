#/bin/bash
RequestedVersion="$1"

kubectl get nodes >/dev/null
if [ "$?" -ne 0 ]; then
	echo "Cannot list nodes, please ensure you can run kubectl and try again"
	exit 1
else
	echo "kubectl connection OK"
fi

if [ -z "$RequestedVersion" ] || [ -z $(echo "$RequestedVersion" | grep '^[0-9]\.[0-9]\.[0-9]\.[0-9][0-9][0-9]$') ]; then
	echo "ERROR: This command takes one argument, in the format Major.Minor.Micro.Build (ex.: 6.4.0.800). The argument provided was: $RequestedVersion"
	exit 1
fi

kubectl set image deployment/aifrontend netgovernai=netgovern/ai:$RequestedVersion
kubectl set image deployment/aiworker netgovernai=netgovern/ai:$RequestedVersion
kubectl set image deployment/nlpfrontend netgovernnlp=netgovern/nlp:$RequestedVersion
kubectl set image deployment/nlpworker netgovernnlp=netgovern/nlp:$RequestedVersion

echo "Version updated, please run 'kubectl get pods' to monitor rollout."