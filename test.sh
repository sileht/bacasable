
N=$1

touch test-p$N.txt
git add test-p$N.txt
git commit -m "Add test-p$N.txt" 
git push origin main
