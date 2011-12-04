((sel) ->

    ### util.coffee ###

    html = document.documentElement
    
    extend = (a, b) ->
        for x in b
            a.push(x)
    
        return a
        
    eachElement = (el, first, next, fn) ->
        el = el[first]
        while (el)
            fn(el) if el.nodeType == 1
            el = el[next]
            
        return

    nextElementSibling =
        if html.nextElementSibling
            (el) -> el.nextElementSibling
        else
            (el) ->
                el = el.nextSibling
                while (el and el.nodeType != 1)
                    el = el.nextSibling
                
                return el

    contains =
        if html.compareDocumentPosition?
            (a, b) -> (a.compareDocumentPosition(b) & 16) == 16
    
        else if html.contains?
            (a, b) ->
                if a.documentElement then b.ownerDocument == a
                else a != b and a.contains(b)
                
        else
            (a, b) ->
                if a.documentElement then return b.ownerDocument == a
                while b = b.parentNode
                    return true if a == b

                return false

    elCmp =
        if html.compareDocumentPosition
            (a, b) ->
                if a == b then 0
                else if a.compareDocumentPosition(b) & 4 then -1
                else 1
                
        else if html.sourceIndex                                                    
            (a, b) ->
                if a == b then 0
                else if a.sourceIndex < b.sourceIndex then -1
                else 1

    # Return the topmost ancestors of the element array
    filterDescendants = (els) -> els.filter (el, i) -> el and not (i and (els[i-1] == el or contains(els[i-1], el)))

    # Return descendants one level above the given elements
    outerDescendants = (els) ->
        r = []
        
        filterDescendants(els).forEach (el) ->
            parent = el.parentNode
            if parent and parent != r[r.length-1]
                r.push(parent)
                
            return
            
        return r

    # Helper function for combining sorted element arrays in various ways
    combine = (a, b, aRest, bRest, map) ->
        r = []
        i = 0
        j = 0

        while i < a.length and j < b.length
            switch map[elCmp(a[i], b[j])]
                when -1 then i++
                when -2 then j++
                when 1 then r.push(a[i++])
                when 2 then r.push(b[j++])
                when 0
                    r.push(a[i++])
                    j++

        if aRest
            while i < a.length
                r.push(a[i++])

        if bRest
            while j < b.length
                r.push(b[j++])

        return r
    
    # Define these operations in terms of the above element operations to reduce code size
    sel.union = (a, b) -> combine a, b, true, true, {'0': 0, '-1': 1, '1': 2}
    sel.intersection = (a, b) -> combine a, b, false, false, {'0': 0, '-1': -1, '1': -2}
    sel.difference = (a, b) -> combine a, b, true, false, {'0': -1, '-1': 1, '1': -2}

    ### find.coffee ###

    # Attributes that we get directly off the node
    _attrMap = {
        'tag': (el) -> el.tagName
        'class': (el) -> el.className
    }
    
    # Fix buggy getAttribute for urls in IE
    do ->
        p = document.createElement('p')
        p.innerHTML = '<a href="#"></a>'
        
        if p.firstChild.getAttribute('href') != '#'
            _attrMap['href'] = (el) -> el.getAttribute('href', 2)
            _attrMap['src'] = (el) -> el.getAttribute('src', 2)

    # Map of all the positional pseudos and whether or not they are reversed
    _positionalPseudos = {
        'nth-child': false
        'nth-of-type': false
        'first-child': false
        'first-of-type': false

        'nth-last-child': true
        'nth-last-of-type': true
        'last-child': true
        'last-of-type': true

        'only-child': false
        'only-of-type': false
    }
    

    find = (e, roots) ->
        if e.id
            # Find by id
            els = []
            roots.forEach (root) ->
                el = (root.ownerDocument or root).getElementById(e.id)
                els.push(el) if el and contains(root, el)
                return # prevent useless return from forEach
            
            # Don't need to filter on id
            e.id = null
        
        else if e.classes and html.getElementsByClassName
            # Find by class
            els = roots.map((root) ->
                e.classes.map((cls) ->
                    root.getElementsByClassName(cls)
                ).reduce(sel.union)
            ).reduce(extend, [])

            # Don't need to filter on class
            e.classes = null
        
        else
            # Find by tag
            els = roots.map((root) ->
                root.getElementsByTagName(e.tag or '*')
            ).reduce(extend, [])

            # Don't need to filter on tag
            e.tag = null

        if els and els.length
            return filter(e, els)
        else
            return []


    filter = (e, els) ->
        if e.id
            # Filter by id
            els = els.filter((el) -> el.id == e.id)
            
        if e.tag and e.tag != '*'
            # Filter by tag
            els = els.filter((el) -> el.nodeName.toLowerCase() == e.tag)
        
        if e.classes
            # Filter by class
            e.classes.forEach (cls) ->
                els = els.filter((el) -> " #{el.className} ".indexOf(" #{cls} ") >= 0)
                return # prevent useless return from forEach

        if e.attrs
            # Filter by attribute
            e.attrs.forEach ({name, op, val}) ->
                
                els = els.filter (el) ->
                    attr = if _attrMap[name] then _attrMap[name](el) else el.getAttribute(name)
                    value = attr + ""
            
                    return (attr or (el.attributes and el.attributes[name] and el.attributes[name].specified)) and (
                        if not op then true
                        else if op == '=' then value == val
                        else if op == '!=' then value != val
                        else if op == '*=' then value.indexOf(val) >= 0
                        else if op == '^=' then value.indexOf(val) == 0
                        else if op == '$=' then value.substr(value.length - val.length) == val
                        else if op == '~=' then " #{value} ".indexOf(" #{val} ") >= 0
                        else if op == '|=' then value == val or (value.indexOf(val) == 0 and value.charAt(val.length) == '-')
                        else false # should never get here...
                    )

                return # prevent useless return from forEach
            
        if e.pseudos
            # Filter by pseudo
            e.pseudos.forEach ({name, val}) ->

                pseudo = sel.pseudos[name]
                if not pseudo
                    throw new Error("no pseudo with name: #{name}")
        
                if name of _positionalPseudos
                    first = if _positionalPseudos[name] then 'lastChild' else 'firstChild'
                    next = if _positionalPseudos[name] then 'previousSibling' else 'nextSibling'
            
                    els.forEach (el) ->
                        if (parent = el.parentNode) and parent._sel_children == undefined
                            indices = { '*': 0 }
                            eachElement parent, first, next, (el) ->
                                el._sel_index = ++indices['*']
                                el._sel_indexOfType = indices[el.nodeName] = (indices[el.nodeName] or 0) + 1
                                return # prevent useless return from eachElement
                    
                            parent._sel_children = indices
                    
                        return # prevent useless return from forEach
            
                # We need to wait to replace els so we can unset the special attributes
                filtered = els.filter((el) -> pseudo(el, val))

                if name of _positionalPseudos
                    els.forEach (el) ->
                        if (parent = el.parentNode) and parent._sel_children != undefined
                            eachElement parent, first, next, (el) ->
                                el._sel_index = el._sel_indexOfType = undefined
                                return # prevent useless return from eachElement
                                
                            parent._sel_children = undefined
                    
                        return # prevent useless return from forEach
                    
                els = filtered

                return # prevent useless return from forEach
            
        return els
    ### pseudos.coffee ###

    nthPattern = /\s*((?:\+|\-)?(\d*))n\s*((?:\+|\-)\s*\d+)?\s*/;

    checkNth = (i, val) ->
        if not val then false
        else if isFinite(val) then `i == val`       # Use loose equality check since val could be a string
        else if val == 'even' then (i % 2 == 0)
        else if val == 'odd' then (i % 2 == 1)
        else if m = nthPattern.exec(val)
            a = if m[2] then parseInt(m[1]) else parseInt(m[1] + '1')   # Check case where coefficient is omitted
            b = if m[3] then parseInt(m[3].replace(/\s*/, '')) else 0   # Check case where constant is omitted

            if not a then (i == b)
            else (((i - b) % a == 0) and ((i - b) / a >= 0))

        else throw new Error('invalid nth expression')

    sel.pseudos = 
        # See filter() for how el._sel_* values get set
        'first-child': (el) -> el._sel_index == 1
        'only-child': (el) -> el._sel_index == 1 and el.parentNode._sel_children['*'] == 1
        'nth-child': (el, val) -> checkNth(el._sel_index, val)

        'first-of-type': (el) -> el._sel_indexOfType == 1
        'only-of-type': (el) -> el._sel_indexOfType == 1 and el.parentNode._sel_children[el.nodeName] == 1
        'nth-of-type': (el, val) -> checkNth(el._sel_indexOfType, val)

        target: (el) -> (el.getAttribute('id') == location.hash.substr(1))
        checked: (el) -> el.checked == true
        enabled: (el) -> el.disabled == false
        disabled: (el) -> el.disabled == true
        selected: (el) -> el.selected == true
        focus: (el) -> el.ownerDocument.activeElement == el
        empty: (el) -> not el.childNodes.length

        # Extensions
        contains: (el, val) -> (el.textContent ? el.innerText).indexOf(val) >= 0
        with: (el, val) -> select(val, [el]).length > 0
        without: (el, val) -> select(val, [el]).length == 0

    # Pseudo function synonyms
    (sel.pseudos[synonym] = sel.pseudos[name]) for synonym, name of {
        'has': 'with',
        
        # For these methods, the reversing is done in filterPseudo
        'last-child': 'first-child',
        'nth-last-child': 'nth-child',

        'last-of-type': 'first-of-type',
        'nth-last-of-type': 'nth-of-type',
    }
        

    ### parser.coffee ###

    attrPattern = ///
        \[
            \s* ([-\w]+) \s*
            (?: ([~|^$*!]?=) \s* (?: ([-\w]+) | ['"]([^'"]*)['"] ) \s* )?
        \]
    ///g

    pseudoPattern = ///
        ::? ([-\w]+) (?: \( ( \( [^()]+ \) | [^()]+ ) \) )?
    ///g
    
    combinatorPattern = /// ^ \s* ([,+~]) ///
    
    selectorPattern = /// ^ 
        
        (?: \s* (>) )? # child selector
        
        \s*
        
        # tag
        (?: (\* | \w+) )?

        # id
        (?: \# ([-\w]+) )?

        # classes
        (?: \. ([-\.\w]+) )?

        # attrs
        ( (?: #{attrPattern.source} )* )

        # pseudos
        ( (?: #{pseudoPattern.source} )* )

    ///

    selectorGroups = {
        type: 1, tag: 2, id: 3, classes: 4,
        attrsAll: 5, pseudosAll: 10
    }

    parse = (selector) ->
        result = last = parseSimple(selector)
        
        if last.compound
            last.children = []
        
        while last[0].length < selector.length
            selector = selector.substr(last[0].length)
            e = parseSimple(selector)
            
            if e.compound
                e.children = [result]
                result = e
                
            else if last.compound
                last.children.push(e)
                
            else
                last.child = e
                
            last = e

        return result

    parseSimple = (selector) ->
        if e = combinatorPattern.exec(selector)
            e.compound = true
            e.type = e[1]
            
        else if e = selectorPattern.exec(selector)
            e.simple = true

            for name, group of selectorGroups
                e[name] = e[group]

            e.type or= ' '
        
            e.tag = e.tag.toLowerCase() if e.tag
            e.classes = e.classes.toLowerCase().split('.') if e.classes

            if e.attrsAll
                e.attrs = []
                e.attrsAll.replace attrPattern, (all, name, op, val, quotedVal) ->
                    e.attrs.push({name: name, op: op, val: val or quotedVal})
                    return ""

            if e.pseudosAll
                e.pseudos = []
                e.pseudosAll.replace pseudoPattern, (all, name, val) ->
                    if name == 'not'
                        e.not = parse(val)
                    else
                        e.pseudos.push({name: name, val: val})
        
                    return ""
            
        else
            throw new Error("Parse error at: #{selector}")

        return e
    ### eval.coffee ###

    evaluate = (e, roots) ->
        els = []

        if roots.length
            switch e.type
                when ' ', '>'
                    # We only need to search from the outermost roots
                    outerRoots = filterDescendants(roots)
                    els = find(e, outerRoots)

                    if e.type == '>'
                        roots.forEach (el) ->
                            el._sel_mark = true
                            return
                        
                        els = els.filter((el) -> el._sel_mark if (el = el.parentNode))

                        roots.forEach (el) ->
                            el._sel_mark = false
                            return
                            
                    if e.not
                        els = sel.difference(els, find(e.not, outerRoots))
            
                    if e.child
                        els = evaluate(e.child, els)

                when '+', '~', ','
                    if e.children.length == 2
                        sibs = evaluate(e.children[0], roots)
                        els = evaluate(e.children[1], roots)
                    else
                        sibs = roots
                        roots = outerDescendants(roots)
                        els = evaluate(e.children[0], roots)
            
                    if e.type == ','
                        # sibs here is just the result of the first selector
                        els = sel.union(sibs, els)
                    
                    else if e.type == '+'
                        sibs.forEach (el) ->
                            if (el = nextElementSibling(el))
                                el._sel_mark = true 
                                
                            return # prevent useless return from forEach
                            
                        els = els.filter((el) -> el._sel_mark)
                        
                        sibs.forEach (el) ->
                            if (el = nextElementSibling(el))
                                el._sel_mark = undefined
                                
                            return # prevent useless return from forEach
                    
                    else if e.type == '~'
                        sibs.forEach (el) ->
                            while (el = nextElementSibling(el)) and not el._sel_mark
                                el._sel_mark = true
                                
                            return # prevent useless return from forEach
                            
                        els = els.filter((el) -> el._sel_mark)
                        
                        sibs.forEach (el) ->
                            while (el = nextElementSibling(el)) and el._sel_mark
                                el._sel_mark = undefined
                                
                            return # prevent useless return from forEach

        return els

    ### select.coffee ###

    parentMap = {
        thead: 'table',
        tbody: 'table',
        tfoot: 'table',
        tr: 'tbody',
        th: 'tr',
        td: 'tr',
        fieldset: 'form',
        option: 'select',
    }
    
    tagPattern = /^\s*<([^\s>]+)/

    create = (html, root) ->
        parent = (root or document).createElement(parentMap[tagPattern.exec(html)[1]] or 'div')
        parent.innerHTML = html

        els = []
        eachElement parent, 'firstChild', 'nextSibling', (el) -> els.push(el)
        return els

    select =
        # See whether we should try qSA first
        if false && document.querySelector and document.querySelectorAll
            (selector, roots) ->
                try roots.map((root) -> root.querySelectorAll(selector)).reduce(extend, [])
                catch e then evaluate(parse(selector), roots)
        else
            (selector, roots) -> evaluate(parse(selector), roots)

    normalizeRoots = (roots) ->
        if not roots
            return [document]
        
        else if typeof roots == 'string'
            return select(roots, [document])
        
        else if typeof roots == 'object' and isFinite(roots.length)
            roots.sort(elCmp) if roots.sort
            return filterDescendants(roots)
        
        else
            return [roots]

    sel.sel = (selector, _roots) ->
        roots = normalizeRoots(_roots)

        if not selector
            return []
            
        else if Array.isArray(selector)
            return selector
            
        else if tagPattern.test(selector)
            return create(selector, roots[0])
            
        else if selector in [window, 'window']
            return [window]
            
        else if selector in [document, 'document']
            return [document]
            
        else if selector.nodeType == 1
            if not _roots or roots.some((root) -> contains(root, selector))
                return [selector]
            else
                return []
                
        else
            return select(selector, roots)

    sel.matching = (els, selector) -> filter(parse(selector), els)
)(exports ? (@['sel'] = {}))

