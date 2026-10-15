#!/bin/sh
# Re-extract GpodderEpisodeAction from the app source into the harness.
cd "$(dirname "$0")/Sources/GpodderLogic" && python3 - <<'PY'
src=open('../../../AntennaPod/Data/GpodderClient.swift').read()
i=src.index('struct GpodderEpisodeAction: Codable, Equatable {'); d=0
for j in range(i,len(src)):
    if src[j]=='{': d+=1
    elif src[j]=='}':
        d-=1
        if d==0: break
head=open('GpodderEpisodeAction.generated.swift').read().split('\nstruct GpodderEpisodeAction')[0]+'\n'
open('GpodderEpisodeAction.generated.swift','w').write(head+src[i:j+1]+'\n')
PY
