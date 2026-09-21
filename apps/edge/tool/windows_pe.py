"""Portable PE resources for Vynic Windows amd64 builds; no executable post-packing."""
import struct


def align(data):
    return data + bytes((-len(data)) % 4)


def block(key, value=b'', children=b'', text=False):
    payload = align(struct.pack('<HHH', 0, len(value)//2 if text else len(value), int(text)) + (key+'\0').encode('utf-16le'))
    payload = align(payload + value) + children
    return struct.pack('<H', len(payload)) + payload[2:]


def version_info(product, filename, version):
    parts = [int(p) for p in version.split('.')]
    if len(parts) != 4 or any(p < 0 or p > 65535 for p in parts):
        raise ValueError('Windows version requires four uint16 components')
    hi, lo = (parts[0]<<16)|parts[1], (parts[2]<<16)|parts[3]
    fixed = struct.pack('<13I', 0xfeef04bd, 0x10000, hi, lo, hi, lo, 0x3f, 0, 0x40004, 1, 0, 0, 0)
    fields = {'CompanyName':'Vynic', 'ProductName':product, 'FileDescription':product,
              'FileVersion':version, 'ProductVersion':version, 'OriginalFilename':filename,
              'InternalName':filename.removesuffix('.exe'), 'LegalCopyright':'Copyright Vynic. All rights reserved.'}
    strings = b''.join(align(block(k, (v+'\0').encode('utf-16le'), text=True)) for k,v in fields.items())
    children = align(block('StringFileInfo',children=block('040904b0',children=strings,text=True),text=True))
    children += block('VarFileInfo',children=block('Translation',struct.pack('<HH',1033,1200)),text=True)
    return block('VS_VERSION_INFO',fixed,children)


def icon_resources(ico):
    """Convert the existing ICO images into native RT_ICON/RT_GROUP_ICON entries."""
    if len(ico) < 6:
        raise ValueError('truncated icon')
    reserved, kind, count = struct.unpack_from('<HHH', ico)
    if reserved or kind != 1 or not 1 <= count <= 256 or len(ico) < 6 + count*16:
        raise ValueError('invalid icon directory')
    group = bytearray(struct.pack('<HHH', 0, 1, count))
    result = {}
    for i in range(count):
        at = 6 + i*16
        width, height, colors, reserved, planes, bits, size, offset = struct.unpack_from('<BBBBHHII', ico, at)
        if reserved or not size or offset < 6 + count*16 or offset+size > len(ico):
            raise ValueError('invalid icon image')
        result[(3, i+1)] = ico[offset:offset+size]
        group += struct.pack('<BBBBHHIH', width, height, colors, 0, planes, bits, size, i+1)
    result[(14, 1)] = bytes(group)
    return result


def resource(entries):
    """Build amd64 COFF resources: type -> numeric image ID -> en-US."""
    tree = {}
    for key, payload in entries.items():
        kind, ident = key if isinstance(key, tuple) else (key, 1)
        if ident in tree.setdefault(kind, {}):
            raise ValueError('duplicate resource ID')
        tree[kind][ident] = {1033: payload}
    data = bytearray()
    relocations = []
    def directory(nodes):
        start = len(data)
        data.extend(struct.pack('<IIHHHH', 0, 0, 0, 0, 0, len(nodes)))
        data.extend(bytes(len(nodes)*8))
        for i, (ident, node) in enumerate(sorted(nodes.items())):
            if isinstance(node, dict):
                target = 0x80000000 | directory(node)
            else:
                target = len(data)
                data.extend(struct.pack('<IIII', target+16, len(node), 0, 0))
                relocations.append(struct.pack('<IIH', target, 0, 3))
                data.extend(align(node))
            struct.pack_into('<II', data, start+16+i*8, ident, target)
        return start
    directory(tree)
    reloc = b''.join(relocations)
    header = struct.pack('<HHIIIHH', 0x8664, 1, 0, 60+len(data)+len(reloc), 1, 0, 0)
    section = struct.pack('<8sIIIIIIHHI', b'.rsrc', 0, 0, len(data), 60, 60+len(data), 0, len(relocations), 0, 0x40000040)
    symbol = struct.pack('<8sIhHBB', b'.rsrc', 0, 1, 0, 3, 0)
    return header+section+data+reloc+symbol+struct.pack('<I', 4)


def inspect(path):
    image=path.read_bytes()
    if image[:2]!=b'MZ':raise ValueError('not a PE executable')
    pe=struct.unpack_from('<I',image,60)[0]
    if image[pe:pe+4]!=b'PE\0\0':raise ValueError('not PE')
    machine,count=struct.unpack_from('<HH',image,pe+4)
    opt=pe+24
    if machine!=0x8664 or struct.unpack_from('<H',image,opt)[0]!=0x20b:raise ValueError('amd64 required')
    sections=opt+struct.unpack_from('<H',image,pe+20)[0]
    def offset(rva):
        for i in range(count):
            size,start,raw,at=struct.unpack_from('<IIII',image,sections+i*40+8)
            if start<=rva<start+max(size,raw):return at+rva-start
        raise ValueError('resource RVA out of range')
    rva,size=struct.unpack_from('<II',image,opt+128)
    base=offset(rva)
    def entries(at):
        named,ids=struct.unpack_from('<HH',image,base+at+12)
        if named:raise ValueError('expected numeric resources')
        return [struct.unpack_from('<II',image,base+at+16+i*8) for i in range(ids)]
    blobs={}
    for kind,sub in entries(0):
        for ident,langs in entries(sub&0x7fffffff):
            for lang,desc in entries(langs&0x7fffffff):
                ptr,length=struct.unpack_from('<II',image,base+desc)
                blobs[(kind,ident,lang)]=image[offset(ptr):offset(ptr)+length]
    cert_offset,cert_size=struct.unpack_from('<II',image,opt+144)
    return {'machine':'windows/amd64','subsystem':struct.unpack_from('<H',image,opt+68)[0],
            'bytes':len(image),'resources':blobs,'certificateTablePresent':bool(cert_offset and cert_size)}


def version_strings(blob):
    """Read actual StringFileInfo values, rather than matching unrelated strings."""
    result={}
    def walk(start, end):
        length, value_length, kind=struct.unpack_from('<HHH',blob,start)
        stop=start+length
        if length<6 or stop>end:raise ValueError('invalid version block')
        key_end=start+6
        while key_end+2<=stop and blob[key_end:key_end+2]!=b'\0\0':key_end+=2
        if key_end+2>stop:raise ValueError('unterminated version key')
        key=blob[start+6:key_end].decode('utf-16le')
        value_start=(key_end+2+3)&~3
        value_end=value_start+value_length*(2 if kind else 1)
        if value_end>stop:raise ValueError('invalid version value')
        if kind and value_length:
            if key in result:raise ValueError('duplicate version string')
            result[key]=blob[value_start:value_end].decode('utf-16le').rstrip('\0')
        child=(value_end+3)&~3
        while child+6<=stop:
            consumed=walk(child,stop)
            child=(consumed+3)&~3
        return stop
    walk(0,len(blob))
    return result
