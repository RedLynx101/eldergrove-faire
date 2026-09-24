def top_parts(inner):
    parts, depth, cur = [], 0, ''
    for ch in inner:
        if ch in '([{': depth += 1
        if ch in ')]}': depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur); cur = ''
        else:
            cur += ch
    parts.append(cur)
    return parts

def add_field(s, key, n, name):
    out, i = '', 0
    while True:
        j = s.find(key, i)
        if j < 0:
            out += s[i:]; break
        if j > 0 and (s[j-1].isalnum() or s[j-1] in '_.') and not s[:j].endswith('C.'):
            out += s[i:j+len(key)]; i = j+len(key); continue
        k = j + len(key); depth = 1
        while depth:
            if s[k] == '{': depth += 1
            elif s[k] == '}': depth -= 1
            k += 1
        inner = s[j+len(key):k-1]
        if len(top_parts(inner)) == n:
            inner = inner + ', ' + name
        out += s[i:j] + key + inner + '}'
        i = k
    return out

def edit_s(s, pairs, tag=''):
    for a,b in pairs:
        c=s.count(a)
        assert c==1, (tag, a[:80], c)
        s=s.replace(a,b)
    return s
