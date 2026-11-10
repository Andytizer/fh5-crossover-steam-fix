import sys,struct
def rd(path):
    b=open(path,'rb').read()
    pe=struct.unpack_from('<I',b,0x3c)[0]
    ns,=struct.unpack_from('<H',b,pe+6); osz,=struct.unpack_from('<H',b,pe+20)
    opt=pe+24; magic,=struct.unpack_from('<H',b,opt)
    dd=opt+(112 if magic==0x20b else 96)
    erva,esz=struct.unpack_from('<II',b,dd)
    secs=[struct.unpack_from('<8sIIII',b,opt+osz+i*40) for i in range(ns)]
    def off(r):
        for n,vs,va,rs,rp in secs:
            if va<=r<va+max(vs,rs): return r-va+rp
        raise Exception(hex(r))
    e=off(erva)
    base,nf,nn=struct.unpack_from('<III',b,e+16)
    af,an,ao=struct.unpack_from('<III',b,e+28)
    names={}
    for i in range(nn):
        nr,=struct.unpack_from('<I',b,off(an)+4*i); o,=struct.unpack_from('<H',b,off(ao)+2*i)
        s=off(nr); names[o]=b[s:b.index(b'\0',s)].decode()
    out=[]
    for i in range(nf):
        r,=struct.unpack_from('<I',b,off(af)+4*i)
        if r==0: continue
        fwd = erva<=r<erva+esz
        out.append((base+i,names.get(i),fwd))
    return out
if __name__=='__main__':
    dll,orig=sys.argv[1],sys.argv[2]
    ex=rd(dll)
    print('LIBRARY',dll.split('/')[-1]); print('EXPORTS')
    import os
    wrapped=set(os.environ.get('WRAP','').split(','))
    for o,n,f in ex:
        if n:
            if n in wrapped: print(f'    {n}=wrap_{n} @{o}')
            else: print(f'    {n}={orig}.{n} @{o}')
        else: print(f'    ord{o}={orig}.#{o} @{o} NONAME')
    sys.stderr.write(f'{len(ex)} exports, {sum(1 for e in ex if not e[1])} noname, {sum(1 for e in ex if e[2])} fwd\n')
