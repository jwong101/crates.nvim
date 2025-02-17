local M = {Section = {}, Crate = {Vers = {}, Path = {}, Git = {}, Pkg = {}, Def = {}, Feat = {}, }, Feature = {}, Quotes = {}, }



































































































local Section = M.Section
local Crate = M.Crate
local Feature = M.Feature
local semver = require("crates.semver")
local types = require("crates.types")
local Range = types.Range
local Requirement = types.Requirement

local function inline_table_bool_pattern(name)
   return "^%s*([^%s]+)%s*=%s*{.-[,]?()%s*" .. name .. "%s*=%s*()([^%s,]*)()%s*()[,]?.*[}]?%s*$"
end

local function inline_table_str_pattern(name)
   return [[^%s*([^%s]+)%s*=%s*{.-[,]?()%s*]] .. name .. [[%s*=%s*(["'])()([^"']*)()(["']?)%s*()[,]?.*[}]?%s*$]]
end

local function inline_table_str_array_pattern(name)
   return "^%s*([^%s]+)%s*=%s*{.-[,]?()%s*" .. name .. "%s*=%s*%[()([^%]]*)()[%]]?%s*()[,]?.*[}]?%s*$"
end

local INLINE_TABLE_VERS_PATTERN = inline_table_str_pattern("version")
local INLINE_TABLE_PATH_PATTERN = inline_table_str_pattern("path")
local INLINE_TABLE_GIT_PATTERN = inline_table_str_pattern("git")
local INLINE_TABLE_PKG_PATTERN = inline_table_str_pattern("package")
local INLINE_TABLE_FEAT_PATTERN = inline_table_str_array_pattern("features")
local INLINE_TABLE_DEF_PATTERN = inline_table_bool_pattern("default[_-]features")

function M.parse_crate_features(text)
   local feats = {}
   for fds, qs, fs, f, fe, qe, fde, c in text:gmatch([[[,]?()%s*(["'])()([^,"']*)()(["']?)%s*()([,]?)]]) do
      table.insert(feats, {
         name = f,
         col = Range.new(fs - 1, fe - 1),
         decl_col = Range.new(fds - 1, fde - 1),
         quote = { s = qs, e = qe ~= "" and qe or nil },
         comma = c == ",",
      })
   end

   return feats
end

function Crate.new(obj)
   if obj.vers then
      obj.vers.reqs = semver.parse_requirements(obj.vers.text)

      obj.vers.is_pre = false
      for _, r in ipairs(obj.vers.reqs) do
         if r.vers.pre then
            obj.vers.is_pre = true
            break
         end
      end
   end
   if obj.feat then
      obj.feat.items = M.parse_crate_features(obj.feat.text)
   end
   if obj.def then
      obj.def.enabled = obj.def.text ~= "false"
   end

   return setmetatable(obj, { __index = Crate })
end

function Crate:vers_reqs()
   return self.vers and self.vers.reqs or {}
end

function Crate:vers_is_pre()
   return self.vers and self.vers.is_pre
end

function Crate:get_feat(name)
   if not self.feat or not self.feat.items then
      return nil
   end

   for i, f in ipairs(self.feat.items) do
      if f.name == name then
         return f, i
      end
   end

   return nil
end

function Crate:feats()
   return self.feat and self.feat.items or {}
end

function Crate:is_def_enabled()
   return not self.def or self.def.enabled
end

function Crate:cache_key()
   return string.format("%s:%s:%s", self.section.target or "", self.section.kind, self.rename or self.name)
end


function M.parse_section(text)
   local prefix, suffix = text:match("^(.*)dependencies(.*)$")
   if prefix and suffix then
      prefix = vim.trim(prefix)
      suffix = vim.trim(suffix)
      local section = {
         text = text,
         invalid = false,
         kind = "default",
      }

      local target = prefix
      local dev_target = prefix:match("^(.*)dev%-$")
      if dev_target then
         target = vim.trim(dev_target)
         section.kind = "dev"
      end

      local build_target = prefix:match("^(.*)build%-$")
      if build_target then
         target = vim.trim(build_target)
         section.kind = "build"
      end

      if target then
         local t = target:match("^target%s*%.(.+)%.$")
         section.target = t and vim.trim(t)
      end

      if suffix then
         local n = suffix:match("^%.(.+)$")
         section.name = n and vim.trim(n)
      end

      section.invalid = prefix ~= "" and not section.target and section.kind == "default" or
      target ~= "" and not section.target or
      suffix ~= "" and not section.name

      return section
   end

   return nil
end

local function parse_crate_table_str(entry, line, pattern)
   local quote_s, str_s, text, str_e, quote_e = line:match(pattern)
   if text then
      return {
         syntax = "table",
         [entry] = {
            text = text,
            col = Range.new(str_s - 1, str_e - 1),
            decl_col = Range.new(0, line:len()),
            quote = { s = quote_s, e = quote_e ~= "" and quote_e or nil },
         },
      }
   end

   return nil
end

function M.parse_crate_table_vers(line)
   local pat = [[^%s*version%s*=%s*(["'])()([^"']*)()(["']?)%s*$]]
   return parse_crate_table_str("vers", line, pat)
end

function M.parse_crate_table_path(line)
   local pat = [[^%s*path%s*=%s*(["'])()([^"']*)()(["']?)%s*$]]
   return parse_crate_table_str("path", line, pat)
end

function M.parse_crate_table_git(line)
   local pat = [[^%s*git%s*=%s*(["'])()([^"']*)()(["']?)%s*$]]
   return parse_crate_table_str("git", line, pat)
end

function M.parse_crate_table_pkg(line)
   local pat = [[^%s*package%s*=%s*(["'])()([^"']*)()(["']?)%s*$]]
   return parse_crate_table_str("pkg", line, pat)
end

function M.parse_crate_table_feat(line)
   local array_s, text, array_e = line:match("%s*features%s*=%s*%[()([^%]]*)()[%]]?%s*$")
   if text then
      return {
         syntax = "table",
         feat = {
            text = text,
            col = Range.new(array_s - 1, array_e - 1),
            decl_col = Range.new(0, line:len()),
         },
      }
   end

   return nil
end

function M.parse_crate_table_def(line)
   local bool_s, text, bool_e = line:match("^%s*default[_-]features%s*=%s*()([^%s]*)()%s*$")
   if text then
      return {
         syntax = "table",
         def = {
            text = text,
            col = Range.new(bool_s - 1, bool_e - 1),
            decl_col = Range.new(0, line:len()),
         },
      }
   end

   return nil
end

local function parse_inline_table_str(crate, entry, line, pattern)
   local name, decl_s, quote_s, str_s, text, str_e, quote_e, decl_e = line:match(pattern)
   if name then
      crate.name = name
      crate.syntax = "inline_table"
      crate[entry] = {
         text = text,
         col = Range.new(str_s - 1, str_e - 1),
         decl_col = Range.new(decl_s - 1, decl_e - 1),
         quote = { s = quote_s, e = quote_e ~= "" and quote_e or nil },
      }
   end
end

function M.parse_crate(line)

   do
      local name, quote_s, str_s, text, str_e, quote_e = line:match([[^%s*([^%s]+)%s*=%s*(["'])()([^"']*)()(["']?)%s*$]])
      if name then
         return {
            name = name,
            syntax = "plain",
            vers = {
               text = text,
               col = Range.new(str_s - 1, str_e - 1),
               decl_col = Range.new(0, line:len()),
               quote = { s = quote_s, e = quote_e ~= "" and quote_e or nil },
            },
         }
      end
   end


   local crate = {}

   parse_inline_table_str(crate, "vers", line, INLINE_TABLE_VERS_PATTERN)
   parse_inline_table_str(crate, "path", line, INLINE_TABLE_PATH_PATTERN)
   parse_inline_table_str(crate, "git", line, INLINE_TABLE_GIT_PATTERN)

   do
      local name, decl_s, array_s, text, array_e, decl_e = line:match(INLINE_TABLE_FEAT_PATTERN)
      if name then
         crate.name = name
         crate.syntax = "inline_table"
         crate.feat = {
            text = text,
            col = Range.new(array_s - 1, array_e - 1),
            decl_col = Range.new(decl_s - 1, decl_e - 1),
         }
      end
   end

   do
      local name, decl_s, bool_s, text, bool_e, decl_e = line:match(INLINE_TABLE_DEF_PATTERN)
      if name then
         crate.name = name
         crate.syntax = "inline_table"
         crate.def = {
            text = text,
            col = Range.new(bool_s - 1, bool_e - 1),
            decl_col = Range.new(decl_s - 1, decl_e - 1),
         }
      end
   end


   do
      local name, decl_s, quote_s, str_s, text, str_e, quote_e, decl_e = line:match(INLINE_TABLE_PKG_PATTERN)
      if name then
         crate.name = text
         crate.rename = name
         crate.syntax = "inline_table"
         crate.pkg = {
            text = text,
            col = Range.new(str_s - 1, str_e - 1),
            decl_col = Range.new(decl_s - 1, decl_e - 1),
            quote = { s = quote_s, e = quote_e ~= "" and quote_e or nil },
         }
      end
   end

   if crate.name then
      return crate
   else
      return nil
   end
end

function M.trim_comments(line)
   local uncommented = line:match("^([^#]*)#.*$")
   return uncommented or line
end

function M.parse_crates(buf)
   local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

   local sections = {}
   local crates = {}

   local dep_section = nil
   local dep_section_crate = nil

   for i, l in ipairs(lines) do
      l = M.trim_comments(l)

      local section_text = l:match("^%s*%[(.+)%]%s*$")

      if section_text then
         if dep_section then

            dep_section.lines.e = i - 1


            if dep_section_crate then
               dep_section_crate.lines = dep_section.lines
               table.insert(crates, Crate.new(dep_section_crate))
            end
         end

         local section = M.parse_section(section_text)

         if section then
            section.lines = Range.new(i - 1, nil)
            dep_section = section
            dep_section_crate = nil
            table.insert(sections, dep_section)
         else
            dep_section = nil
            dep_section_crate = nil
         end
      elseif dep_section and dep_section.name then
         local crate_vers = M.parse_crate_table_vers(l)
         if crate_vers then
            crate_vers.name = dep_section.name
            crate_vers.vers.line = i - 1
            crate_vers.section = dep_section
            dep_section_crate = vim.tbl_extend("keep", dep_section_crate or {}, crate_vers)
         end

         local crate_path = M.parse_crate_table_path(l)
         if crate_path then
            crate_path.name = dep_section.name
            crate_path.path.line = i - 1
            crate_path.section = dep_section
            dep_section_crate = vim.tbl_extend("keep", dep_section_crate or {}, crate_path)
         end

         local crate_git = M.parse_crate_table_git(l)
         if crate_git then
            crate_git.name = dep_section.name
            crate_git.git.line = i - 1
            crate_git.section = dep_section
            dep_section_crate = vim.tbl_extend("keep", dep_section_crate or {}, crate_git)
         end

         local crate_feat = M.parse_crate_table_feat(l)
         if crate_feat then
            crate_feat.name = dep_section.name
            crate_feat.feat.line = i - 1
            crate_feat.section = dep_section
            dep_section_crate = vim.tbl_extend("keep", dep_section_crate or {}, crate_feat)
         end

         local crate_def = M.parse_crate_table_def(l)
         if crate_def then
            crate_def.name = dep_section.name
            crate_def.def.line = i - 1
            crate_def.section = dep_section
            dep_section_crate = vim.tbl_extend("keep", dep_section_crate or {}, crate_def)
         end


         local crate_pkg = M.parse_crate_table_pkg(l)
         if crate_pkg then
            local crate = dep_section_crate or {}
            crate.rename = dep_section.name
            crate.name = crate_pkg.pkg.text

            crate_pkg.pkg.line = i - 1
            crate_pkg.section = dep_section
            dep_section_crate = vim.tbl_extend("keep", crate, crate_pkg)
         end
      elseif dep_section then
         local crate = M.parse_crate(l)
         if crate then
            crate.lines = Range.new(i - 1, i)
            if crate.vers then
               crate.vers.line = i - 1
            end
            if crate.def then
               crate.def.line = i - 1
            end
            if crate.feat then
               crate.feat.line = i - 1
            end
            crate.section = dep_section
            table.insert(crates, Crate.new(crate))
         end
      end
   end

   if dep_section then

      dep_section.lines.e = #lines


      if dep_section_crate then
         dep_section_crate.lines = dep_section.lines
         table.insert(crates, Crate.new(dep_section_crate))
      end
   end

   return sections, crates
end

return M
