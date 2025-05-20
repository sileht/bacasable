
N=$1

git n test-p$N
touch test-p$N.txt
git add test-p$N.txt
git commit -m "Add test-p$N.txt" 
git push origin test-p$N
gh pr create -f --head test-p$N

sleep 3

gh pr checks --watch -i 1
gh pr edit --add-label mergify
gh pr comment -b "@mergifyio queue"

sleep 1

gh pr comment -b "@mergifyio refresh"

for M in $(seq 1 25); do
    git n test-m$N-$M
    touch test-m$N-$M
    git add test-m$N-$M
    git commit -m "Add test-m$N-$M" 
    git push origin test-m$N-$M
    gh pr create -f --head test-m$N-$M
    gh pr merge --admin --rebase
    sleep 0.5
done
