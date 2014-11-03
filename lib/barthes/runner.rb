require 'json'
require 'barthes/action'
require 'barthes/reporter'
require 'barthes/cache'

module Barthes
	class Runner
		def initialize(options)
			load_cache
			load_config
			load_envs(options[:env])
			@reporter = Reporter.new(options)
			@options = options
		end

		def load_cache
			path = Dir.pwd + '/barthes-cache.json'
			if File.exists?(path)
				Barthes::Cache.load JSON.parse File.read(path)
			end
		end

		def load_config
			path = Dir.pwd + '/.barthes'
			load path if File.exists?(path)
		end

		def load_envs(env_paths)
			@env = {}
			env_paths.each do |path|
				@env.update JSON.parse File.read(path)
			end
		end

		def expand_paths(paths, suffix)
			files = []
			if paths.empty?
				files += Dir["./**/*#{suffix}"]
			else
				paths.each do |path|
					if FileTest.directory?(path)
						files += Dir["#{path}/**/*#{suffix}"]
					elsif FileTest.file?(path)
						files << path
					end
				end
			end
			files
		end

		def run(paths)
			files = expand_paths(paths, '_spec.json')
			@reporter.report(:run, files) do
				@num = 1
				results = []
				files.each do |file|
					json = JSON.parse File.read(file)
					@reporter.report(:feature, @num, json[1]) do
						@num += 1
						#Barthes::Cache.reset ## load config or reset
						feature_results = walk_json(json.last, [file])
						results += results
					end
				end
				results
			end
			puts JSON.pretty_generate Barthes::Cache.to_hash
		end

		def in_range?
			flag = @num >= @options[:from]
			flag = flag && (@num >= @options[:to]) if @options[:to]
			flag
		end
	
		def walk_json(json, scenarios)
			if json.class == Array
				case json.first
				when 'scenario'
					handle_scenario(json, scenarios)
					@num += 1
					scenarios.push(json.first)
					walk_json(json.last, scenarios)
					scenarios.pop
				when 'action'
					handle_action(json, scenarios) if in_range?
					@num += 1
				else
					json.each do |element|
						walk_json(element, scenarios)
					end
				end
			end
		end
	
		def handle_scenario(scenario, scenarios)
			return if @failed
			@reporter.report(:scenario, @num, scenario[1], scenario.last, scenarios) do
			end
		end
	
		def handle_action(action, scenarios)
			return if @failed
			name, content = action[1], action.last
			env = @env.dup
			env.update(content['environment']) if content['environment']
			@reporter.report(:action, @num, name, action.last, scenarios) do
				if !@options[:dryrun] && !@failed
					content = Action.new(env, @options).action(content)
					if content['expectations'] && content['expectations'].any? {|e| e['result'] == false }
						@failed = true
					end
				end
				content
			end
		end
	end
end
