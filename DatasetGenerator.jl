using PyCall

# No mimetype library in Julia (???)
function __init__()
    py"""
    import mimetypes

    def get_mime(x):
        return mimetypes.guess_type(x)[0]
    """
end

# Returns all text files in path and its subfolders as one string
function processDatasetFolder(path)
    contents = String[]
    for (root, dirs, files) in walkdir(path)
        for (i, file) in enumerate(files)
            fpath = joinpath(root, file)
            mime = py"get_mime"(fpath)
            if mime != nothing && Base.Multimedia.istextmime(mime)
                open(fpath, "r") do f
                    push!(contents, read(f, String) * "\n\n")
                end
            end
        end
    end

    strip(join(contents))
end

function processDataFolderIntoTextFile(srcfolder, destfile, overwrite=false)
    if !overwrite && isfile(destfile)
        return
    end

    dataset = processDatasetFolder(srcfolder)

    # TODO instead of removing links, put shortcuts for ctrl+c and ctrl+v
    # TODO map all data into shortcuts
    # Remove links, since we normally copy paste them instead of writing them
    urlregex = r"(http(s)?:\/\/.)(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)"
    dataset = replace(dataset, urlregex => "")

    open(destfile, "w") do f
        write(f, dataset)
    end
end

processDataFolderIntoTextFile("data/raw_dataset", "data/dataset.txt", false)
