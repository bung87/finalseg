# finalseg
# Copyright zhoupeng
# jieba's finalseg port to nim
import os
import json
import tables
import future
import nre
import unicode

const
    MIN_FLOAT = -3.14e100
    PrevStatus = {
        "B": "ES",
        "M": "MB",
        "S": "SE",
        "E": "BM"
    }.toTable

template filename: string = instantiationInfo().filename
let appDir = parentDir(filename())
let prob_start = parseFile(appDir / "prob_start.json")
let prob_trans = parseFile(appDir / "prob_trans.json")
let prob_emit = parseFile(appDir  / "prob_emit.json")

type
    ProbState = tuple[prob: float, state: string]
    ProbState2 = tuple[prob: float, state: seq[string]]
var Force_Split_Words:seq[string] = @[]

proc viterbi(obs:string, states:string, start_p:JsonNode, trans_p:JsonNode, emit_p:JsonNode):ProbState2 = 
    let runeLen = obs.runeLen()
    var 
        V = %*[{}]  # tabular
        path = %*{}
    for k in states:  # init
        let 
            y = $k
            y2 = runeStrAtPos(obs,0)
            sp = if start_p.hasKey(y) : start_p[y].getFloat(MIN_FLOAT) else:MIN_FLOAT
            ep =  if emit_p[y].hasKey(y2) : emit_p[y][y2].getFloat(MIN_FLOAT) else:MIN_FLOAT
        V[0][y] = %* (sp + ep)
        path[y] = %* [y]

    for t in 1..runeLen - 1:
        V.add(%*{})
        let 
            newpath = %*{}
        for k in states:
            let
                y = $k
                y2 = runeStrAtPos(obs,t)
                em_p = if emit_p[y].hasKey(y2) : emit_p[y][y2].getFloat( MIN_FLOAT) else:MIN_FLOAT

            var a:seq[ProbState] = @[]
            for y0 in PrevStatus[y]:
                let 
                    y2 = $y0 
                    ty = trans_p[y2]
                    vPre = V[t - 1]
                    p1 = if vPre.hasKey(y2) :vPre[y2].getFloat(MIN_FLOAT) :else:MIN_FLOAT
                    p2 = if ty.hasKey(y):ty[y].getFloat( MIN_FLOAT) else:MIN_FLOAT
                    prob = p1 + p2 + em_p
                    ps:ProbState = (prob:prob,state:y2)
                a.add(ps)
            let fps = max(a)
            V[t][y] = %* fps.prob
            var
                r = lc[y.getStr() | (y <- path[fps.state].getElems()),string ]
            r.add(y)
            newpath[y] = %* r
        path = newpath
    let 
        ps:ProbState = max( lc[(prob:if V[runeLen - 1].hasKey($y) :V[runeLen - 1][$y].getFloat(MIN_FLOAT) else:MIN_FLOAT, state: $y) | (y <- "ES" ),ProbState])
        r:ProbState2 = (prob: ps.prob,state:lc[y.getStr() | (y <- path[ps.state].getElems()),string ] )
    return r


proc internal_cut(sentence:string):seq[string]  =
    let mp = viterbi(sentence, "BMES", prob_start, prob_trans, prob_emit)
    var 
        begin = 0
        nexti =  0
        result = newSeq[string]()

    for i in 0..< sentence.runeLen()  :
        let pos = mp.state[i]
        if pos == "B":
            begin = i
        elif pos == "E":
            let ed = i + 1
            result.add( runeSubStr(sentence,begin,ed-begin) )
            nexti = i + 1
        elif pos == "S":
            result.add(runeStrAtPos(sentence,i))
            nexti = i + 1
    if nexti < sentence.runeLen():
        result.add( runeSubStr(sentence,nexti,sentence.runeLen()-nexti))
    return result

 
let
    re_han = re(r"(*UTF)([\x{4E00}-\x{9FD5}]+)")
    re_skip = re(r"([a-zA-Z0-9]+(?:\.\d+)?%?)")

proc add_force_split*(word:string) = 
    Force_Split_Words.add(word)

proc cut*(sentence:string):seq[string] {.discardable.} = 
    var result = newSeq[string]()
    if sentence.runeLen() == 0:
        return result
    let blocks:seq[string] = nre.split(sentence,re_han)
    
    for blk in blocks:
        if isSome(blk.match(re_han)) == true:
            let sl:seq[string] = internal_cut(blk)
            for word in sl:
                if ($word in Force_Split_Words == false):
                    result.add( $word)
                else:
                    for c in $word:
                        result.add( $c )
        else:
            let tmp = split(blk,re_skip)
            for x in tmp:
                if x.runeLen()>0:
                    result.add( x)
    return result