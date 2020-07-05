module PandocTools

export replace_fence, replace_blurbs, recursive_replace_blurbs, fix_id_attrs
export mdfiles, svgfiles

mdfiles() = filter(file -> endswith(file, ".md"), readdir())
svgfiles() = filter(file -> endswith(file, ".svg"), readdir())


function single_replace_fence(filename::AbstractString, subst::Pair = "julia"=>"~~~")
    out = IOBuffer()
    lineno = 0
    open(filename) do io
        while !eof(io)
            lang = first(subst)
            s = readuntil(io, "```$lang\n")
            write(out, s)
            lineno += count(==('\n'), s)
            
            if eof(io)
                break
            end
            
            write(out, last(subst), "\n")
            lineno += 1
            s = readuntil(io, "```")
            write(out, s)
            lineno += count(==('\n'), s)
            
            write(out, last(subst))
        end
    end
    seekstart(out)
    s = read(out, String)
    close(out)
    open(filename, "w") do io
        write(io, s)
    end    
end

function replace_fence(dir::AbstractString, replacement::Pair = "julia"=>"~~~"; recursive::Bool=false)
    if recursive
        cd(dir) do
           for filename in mdfiles()
               single_replace_fence(filename, replacement)   
           end 
        end
    
        cd(dir) do
            for d in filter(isdir, readdir())
                replace_fence(d, replacement, recursive=true)
            end
        end
    else
        single_replace_fence(dir, replacement)
    end
end

"""
    replace_blurbs(dir)

Replace sections such as `!!! info "Foobar"` boxes with a Pandoc equivalent

    > **INFO Foobar**
    >
    > main text
"""
function replace_blurbs(dir::AbstractString)
    cd(dir) do
        for filename in mdfiles()
            lines = readlines(filename)
            rlines = String[]
            lineno = 1
            while lineno <= length(lines)
                line = lines[lineno]
                # Don't do anything with lines which don't begin with a blurb
                if !startswith(line, "!!!")
                    lineno += 1
                    push!(rlines, line)
                    continue
                end
                
                # simply assume there is no header until proven wrong
                admonition = strip(line[4:end])
                
                I = findall(==('"'), line)
                if !isempty(I)
                    admonition = strip(line[4:first(I)-1])
                    push!(rlines, string("> **", uppercase(admonition), " ", line[first(I)+1:last(I)-1], "**"))
                else
                    push!(rlines, string("> **", uppercase(admonition), "**"))
                end
                push!(rlines, ">")
                
                lineno += 1
                while lineno <= length(lines)
                    line = lines[lineno]
                    if !startswith(line, "  ")
                       break 
                    end
                    push!(rlines, string("> ", strip(line)))
                    lineno += 1
                end
            end
            
            open(filename, "w") do io
                for line in rlines
                    println(io, line)
                end
            end
        end
    end    
end

function recursive_replace_blurbs(dir::AbstractString)
    replace_blurbs(dir)
    cd(dir) do
        for d in filter(isdir, readdir())
            recursive_replace_blurbs(d)    
        end
    end    
end

isident(ch::Char) = isletter(ch) || isnumeric(ch) || ch == '_'

"""
    fix_id_attrs(dir)
Looks at all `.svg` files in directory `dir` and make sure that the XML `id` attrs
don't contain special characters such as :, - or space. They have to look like regular identifiers.
We make it simple by replacing every non-alphanumeric is replaced with underscore.

Why is this useful? Because the epub 3.2 standard does not allow these kinds of identifiers. 
"""
function fix_id_attrs(file::AbstractString)    
    txt = read(file, String)
    rx = r"id=\"[^\"]+\""
    ranges = findall(rx, txt)
    ids = [s[5:end-1] for s in getindex.(txt, ranges)]
    ids = filter(id -> !all(isident, id) || !isletter(id[1]), ids)
    
    for id in ids
        chars = replace(ch -> isident(ch) ? ch : '_', collect(id))
        # first char must be a letter in identifier
        if !isletter(chars[1])
            chars[1] = '_' # use a char unlikely to start an identifier
        end
        legal_id = join(chars)
        txt = replace(txt, "\"$id\"" => "\"$legal_id\"")
    end
    write(file, txt)
end

end # module
