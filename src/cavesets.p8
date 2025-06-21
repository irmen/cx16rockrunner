; Caveset file loader

%import diskio
%import bdcff
%import strings
%import sorting

cavesets {
    const ubyte FILENAMES_BANK = 2
    const ubyte FILEDATA_BANK = 3
    str caveset_filename = " " * 32
    uword[128] @nosplit filename_pointers

    sub load_filenames() -> ubyte {
        ; all the filenames are stored in a hiram page.
        diskio.chdir("caves")
        cx16.rambank(FILENAMES_BANK)
        ubyte amount = diskio.list_filenames("*.bd", $a000, $2000)
        diskio.chdir("..")

        ; build the table of pointers and sort alphabetically
        cx16.r0 = $a000
        for cx16.r1L in 0 to amount-1 {
            filename_pointers[cx16.r1L] = cx16.r0
            cx16.r0 += strings.length(cx16.r0) + 1
        }
        sorting.shellsort_pointers(&filename_pointers, amount, sorting.string_comparator)
        return amount
    }

    sub get_filename(ubyte number) -> str {
        cx16.rambank(FILENAMES_BANK)
        return filename_pointers[number]
    }

    sub load_caveset(str filename) -> bool {
        caveset_filename = filename     ; make a copy, because we switch ram banks (and others are going to read this filename for display)
        bdcff.cs_file_bank = bdcff.cs_file_ptr = 0
        cx16.rambank(FILEDATA_BANK)
        diskio.chdir("caves")
        cx16.r8 = diskio.load_raw(caveset_filename, $a000)
        diskio.chdir("..")
        if cx16.r8!=0 {
            @(cx16.r8) = 0
            bdcff.cs_file_bank = FILEDATA_BANK
            bdcff.cs_file_ptr = $a000
            return true
        }
        return false
    }
}