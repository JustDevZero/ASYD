class Deploy
  include Misc

  # Parse a line (read the documentation for syntax reference)
  #
  # @param host [String] host to take the data from
  # @param line [String] line to be parsed
  # @return line [String] parsed line
  def self.parse(host, line)
    asyd = host.get_asyd_ip
    if !line.start_with?("#") #the line is a comment
      if line.match(/^<%MONITOR:.+%>/i)
        service = line.match(/^<%MONITOR:(.+)%>/i)[1]
        host.monitor_service(service)
        line = ""
      else
        if line.match(/<%VAR:.+%>/i)
          vars = line.scan(/<%VAR:(.+?)%>/i)
          vars.each do |varcontent|
            varcontent = varcontent[0]
            # Check for default variable value (<%VAR:myvar, default: value%>)
            if varcontent.match(/^(.+),\s?default:\s?(.*)/i)
              defvalue = varcontent.match(/^(.+),\s?default:\s?(.*)/i)
              varname = defvalue[1].strip
              defvalue = defvalue[2].strip
            else
              varname = varcontent
            end
            if !host.opt_vars[varname].nil?
              line.gsub!(/<%VAR:#{Regexp.escape(varcontent)}%>/i, host.opt_vars[varname])
            else
              use_defvalue = true unless defvalue.nil?
              host.hostgroups.each do |hostgroup|
                if !hostgroup.opt_vars[varname].nil?
                  line.gsub!(/<%VAR:#{Regexp.escape(varcontent)}%>/i, hostgroup.opt_vars[varname])
                  use_defvalue = false
                end
              end
              @for_loop.each do |item|
                if item[1][:vars].length > 0
                  var = item[1][:vars].first
                  line.gsub!(/<%VAR:#{Regexp.escape(var.keys[0])}%>/i, var.values[0])
                  use_defvalue = false
                end
              end
              line.gsub!(/<%VAR:#{Regexp.escape(varcontent)}%>/i, defvalue) if use_defvalue
            end
          end
        end
        line.gsub!(/<%ASYD%>/i, asyd) unless asyd.nil?
        line.gsub!(/<%MONIT_PW%>/i, host.monit_pw) unless host.monit_pw.nil?
        line.gsub!(/<%IP%>/i, host.ip) unless host.ip.nil?
        line.gsub!(/<%DIST%>/i, host.dist) unless host.dist.nil?
        line.gsub!(/<%DIST_VER%>/i, host.dist_ver.to_s) unless host.dist_ver.nil?
        line.gsub!(/<%ARCH%>/i, host.arch) unless host.arch.nil?
        line.gsub!(/<%HOSTNAME%>/i, host.hostname) unless host.hostname.nil?
        line.gsub!(/<%PKG_MANAGER%>/i, host.pkg_mgr) unless host.pkg_mgr.nil?
        line.gsub!(/<%SVC_MANAGER%>/i, host.svc_mgr) unless host.svc_mgr.nil?
        line.gsub!(/<%SSH_PORT%>/i, host.ssh_port.to_s) unless host.ssh_port.nil?
      end
    end
    return line
  end

  # Parse a config file (read the documentation for syntax reference)
  #
  # @param host [String] host to take the data from
  # @param cfg [String] config to be parsed
  # @return newconf [Object] temporal file with the parameters substituted by the values
  def self.parse_config(host, cfg)
    begin
      noparse = false
      level_if = 0
      level_nodoit = 0
      doit = true
      skip = false
      newconf = Tempfile.new('conf')
      File.open(cfg, "r").each do |line|
        if !noparse
          m = line.strip.match(/^<% ?if (.+)%>$/)
          if !m.nil?
            # ignore conditions if you are on a nodoit
            if doit
              doit = check_condition(m, host)
              level_nodoit = level_if unless doit
            end
            level_if = level_if + 1
            skip = true
          end
          # check for endifs
          if line.strip.match(/^<% ?endif ?%>$/)
            level_if = level_if - 1
            if level_nodoit == level_if
              doit = true
            end
            skip = true
          end
        end
        if !noparse
          if line.strip.match(/^<% ?noparse ?%>$/)
            noparse = true
            skip = true
          end
        else
          if line.strip.match(/^<% ?\/noparse ?%>$/)
            noparse = false
            skip = true
          end
        end
        if doit && !skip
          line = parse(host, line) unless noparse
          newconf << line
        end
        skip = false
      end
    ensure
      newconf.close
    end
    return newconf
  end

  # Parse recursively an entire config directory
  #
  def self.parse_config_dir(host, cfg_dir, tmpath)
    if tmpath.nil?
      o = [('a'..'z'), ('A'..'Z')].map { |i| i.to_a }.flatten
      tmpath = (0...8).map { o[rand(o.length)] }.join
    end
    tempdir = "/tmp/"+tmpath+"/"

    dirs = Misc::get_dirs(cfg_dir)
    files = Misc::get_files(cfg_dir)
    FileUtils.mkdir_p(tempdir)
    files.each do |file|
      parsed_cfg = parse_config(host, cfg_dir+"/"+file)
      FileUtils.mv parsed_cfg.path, tempdir+file
    end
    dirs.each do |dir|
      parse_config_dir(host, cfg_dir+"/"+dir, tmpath+"/"+dir)
    end
    return tempdir
  end

  # Checks conditionals on dep file
  #
  def self.check_condition(m, host)
    statements = Array.new
    i = 0
    conditions = m[1].split(' ')
    conditions.each do |cond|
      if cond == "and" || cond == "or"
        i += 1
        if statements[i].nil?
          statements[i] = cond
        else
          statements[i] << cond
        end
        i += 1
      else
        if statements[i].nil?
          statements[i] = cond
        else
          statements[i] << cond
        end
      end
    end
    comply = false
    comply_prev,comply_curr = false,false
    vand,vor = false,false
    statements.each do |st|
      if st == "and"
        vand = true
      elsif st == "or"
        vor = true
      else
        if vand
          ret = evaluate_condition(st, host)
          if ret
            comply_curr = true
          else
            comply_curr = false
          end
          if comply_prev && comply_curr
            comply = true
            comply_prev = comply_curr
          else
            comply = false
            comply_prev = false
          end
          vand = false
        elsif vor
          ret = evaluate_condition(st, host)
          if ret
            comply_curr = true
          else
            comply_curr = false
          end
          if comply_prev || comply_curr
            comply = true
            if comply_prev
              break
            else
              comply_prev = true
            end
          else
            comply,comply_prev = false,false
          end
          vor = false
        else
          ret = evaluate_condition(st, host)
          if ret
            comply,comply_prev,comply_curr = true,true,true
          end
        end
      end
    end
    return comply
  end

  # Evaluate conditional
  #
  def self.evaluate_condition(st, host)
    st = parse(host, st)

    condition = st.match(/(.+)(==|!=|>=|<=)(.+)/)
    case condition[2]
    when "=="
      if condition[1].nan? || condition[3].nan?
        if condition[1].downcase == condition[3].downcase
          return true
        else
          return false
        end
      else
        if condition[1].to_f == condition[3].to_f
          return true
        else
          return false
        end
      end
    when "!="
      if condition[1].nan? || condition[3].nan?
        if condition[1].downcase == condition[3].downcase
          return false
        else
          return true
        end
      else
        if condition[1].to_f == condition[3].to_f
          return false
        else
          return true
        end
      end
    when ">="
      if condition[1].to_f >= condition[3].to_f
        return true
      else
        return false
      end
    when "<="
      if condition[1].to_f <= condition[3].to_f
        return true
      else
        return false
      end
    else
      return false
    end
  end

  # Get all the sub-variables on a for loop
  #
  def self.parse_var_array(host, search_key, new_varname)
    hash = Array.new
    regex = "^"+search_key.match(/<%VAR:(.+?)%>/i)[1].strip
    (regex.gsub!(/\[/, "\\["); regex.gsub!(/\*/, ".*"); regex.gsub!(/\]/, "?\\]"))
    matching_vars = host.opt_vars.select { |key, value| key.to_s.match(Regexp.new(regex)) }
    if !matching_vars.nil? and !matching_vars.empty?
      i = 0
      matching_vars.each {|key, value|
        hash[i] = {}
        hash[i][new_varname+key.gsub(Regexp.new(regex), "")] = value
        i = i+1
      }
      return hash
    else
      host.hostgroups.each do |hostgroup|
        matching_vars = hostgroup.opt_vars.select { |key, value| key.to_s.match(/^regex/) }
        if !matching_vars.nil? and !matching_vars.empty?
          i = 0
          matching_vars.each {|key, value|
            hash[i] = {}
            hash[i][new_varname+key.gsub(Regexp.new(regex), "")] = value
            i = i+1
          }
          return hash
        end
      end
      return {:error => "Variable "+search_key+" not found on host of hostgroup"}
    end
  end

end
