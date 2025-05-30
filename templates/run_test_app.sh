#!/usr/bin/bash
set -e

DIR=$(pwd)

nix shell --accept-flake-config .#hc-scaffold-happ --command bash -c "
cd /tmp
rm -rf forum-lit-scaffolding

hc-scaffold web-app forum-lit-scaffolding --package-manager pnpm
"

cd /tmp/forum-lit-scaffolding

nix develop --no-update-lock-file --accept-flake-config --override-input scaffolding "path:$DIR" --command bash -c "
set -e

hc-scaffold dna forum 

hc-scaffold zome posts --integrity dnas/forum/zomes/integrity/ --coordinator dnas/forum/zomes/coordinator/
hc-scaffold entry-type post --reference-entry-hash false --crud crud --link-from-original-to-each-update true --fields title:String:TextField,needs:Vec\<String\>:TextField
hc-scaffold entry-type comment --reference-entry-hash false --crud crud --link-from-original-to-each-update false --fields post_hash:ActionHash::Post
hc-scaffold entry-type like --reference-entry-hash false --crud crd --fields like_hash:Option\<ActionHash\>::Like,image_hash:EntryHash:Image,agent:AgentPubKey:SearchUser
hc-scaffold entry-type certificate --reference-entry-hash false --crud cr --fields post_hash:ActionHash::Post,agent:AgentPubKey::certified,certifications_hashes:Vec\<EntryHash\>::Certificate,certificate_type:Enum::CertificateType:TypeOne.TypeTwo,dna_hash:DnaHash

hc-scaffold collection global all_posts post 
hc-scaffold collection by-author posts_by_author post
hc-scaffold collection global all_posts_entry_hash post:EntryHash
hc-scaffold collection by-author posts_by_author_entry_hash post:EntryHash

hc-scaffold link-type post like --delete true --bidirectional false
hc-scaffold link-type comment like --delete true --bidirectional false
hc-scaffold link-type certificate like --delete false --bidirectional false
hc-scaffold link-type agent:creator post --delete false --bidirectional false

git add .

nix flake lock

pnpm install
echo 'lockfile=false' > .npmrc

nix run github:darksoil-studio/profiles-zome/main-0.5#scaffold -- --ci
nix run github:darksoil-studio/file-storage/main-0.5#scaffold -- --ci

pnpm -F ui format
pnpm -F ui lint
pnpm -F ui build

pnpm test
"
