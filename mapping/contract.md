# mapping

The program's folders: which class file each name reaches.

- `mapping.spite`: the entry, `Mapping(folder)`; its `run` answers a `folder_map.spite`.
- `mapped_folder.spite`, `class_file.spite` and `library_file.spite`: a folder, a class file and a library file of the map.
- `standard_library.spite`: the singleton holding the library's folder and system, chosen once by `command_line`;
  it says whether a path is the library's and shows a library file as `spite_standard_library://common/list.spite`.
  `library_load.spite` is what `validators/mapping/library_load` is handed about a `load`.
- `packages.spite` and `pinned_copy.spite`: the package a path belongs to and the copy of a git-pinned one.
- `names.spite`: the last segment of a path, and the one right spelling of a name.
- `misnamed.spite`: a file or folder of the program not named in snake_case that has one right spelling; the map
  notes it instead of refusing it and names its classes by the right spelling, and `fixes/symbols/misnamed_path` renames it.

What it finds wrong is handed to the rules of `validators/mapping`.
