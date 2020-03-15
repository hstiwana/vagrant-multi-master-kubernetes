for x in node3 node2 node1 kmaster3 kmaster2 kmaster1 lb
do
	echo "======================================================================="
	echo "Cleaning up $x VM"
	echo "======================================================================="
vagrant ssh $x -c 'sudo su -c "/vagrant/cleanup.sh"'
done
