#!/bin/bash

# 自动检测项目信息
function find_xcodeproj() {
    local xcodeproj_path=$(find . -maxdepth 1 -name "*.xcodeproj" -type d | head -n 1)
    if [ -z "$xcodeproj_path" ]; then
        echo "错误：未找到 .xcodeproj 文件"
        exit 1
    fi
    echo $(basename "$xcodeproj_path" .xcodeproj)
}

# 自动检测 target 名称
function find_target() {
    local project_name=$1
    if [ ! -f "${project_name}.xcodeproj/project.pbxproj" ]; then
        echo "$project_name"
        return
    fi
    local target_name=$(grep -A 5 "PBXNativeTarget" "${project_name}.xcodeproj/project.pbxproj" | grep -o '".*"' | head -n 1 | sed 's/"//g')
    if [ -z "$target_name" ]; then
        echo "$project_name"
    else
        echo "$target_name"
    fi
}

# 检测 Info.plist 路径
function find_info_plist() {
    local project_name=$1
    local default_path="${project_name}/Info.plist"
    
    if [ -f "$default_path" ]; then
        echo "$default_path"
    else
        local found_path=$(find . -name "Info.plist" -not -path "*/Pods/*" -not -path "*/.build/*" | head -n 1)
        if [ -z "$found_path" ]; then
            echo "$default_path"
        else
            echo "${found_path#./}"
        fi
    fi
}

# 检测新文件
function find_new_files() {
    local project_name=$1
    local pbxproj="${project_name}.xcodeproj/project.pbxproj"
    
    # 查找所有 Swift 文件
    local all_files=$(find . -name "*.swift" -not -path "*/Pods/*" -not -path "*/.build/*")
    
    # 对于每个文件，检查是否已在项目中
    for file in $all_files; do
        # 移除 ./ 前缀
        file=${file#./}
        # 检查文件是否在 project.pbxproj 中
        if ! grep -q "$(basename "$file")" "$pbxproj"; then
            echo "$file"
        fi
    done
}

# 添加文件到项目
function add_file_to_project() {
    local project_name=$1
    local target_name=$2
    local file_path=$3
    
    # 使用 ruby 脚本添加文件
    ruby -e "
require 'xcodeproj'

def ensure_group_exists(project, path_components)
  current_group = project.main_group
  
  # 找到项目组
  project_group = current_group.children.find { |child| 
    child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == '${project_name}'
  }
  
  if project_group.nil?
    puts '错误: 找不到项目组'
    return nil
  end
  
  current_group = project_group
  
  # 遍历路径组件
  path_components.each do |component|
    next if component.empty?
    
    # 在当前组中查找子组
    child_group = current_group.children.find { |child|
      child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == component
    }
    
    # 如果子组不存在，创建它
    if child_group.nil?
      child_group = current_group.new_group(component)
      child_group.path = component
      child_group.source_tree = '<group>'
    end
    
    current_group = child_group
  end
  
  current_group
end

begin
  # 打开项目
  project = Xcodeproj::Project.open('${project_name}.xcodeproj')
  target = project.targets.find { |t| t.name == '${target_name}' }
  
  if target
    # 获取文件路径组件（移除项目名前缀）
    path = '${file_path}'.sub(/^${project_name}\//, '')
    path_components = File.dirname(path).split('/')
    
    # 确保组存在
    group = ensure_group_exists(project, path_components)
    
    if group
      # 获取文件名
      file_name = File.basename('${file_path}')
      
      # 删除现有的文件引用（如果存在）
      existing_file = group.files.find { |f| f.display_name == file_name }
      existing_file.remove_from_project if existing_file
      
      # 添加文件引用
      file_ref = group.new_reference(file_name)
      file_ref.source_tree = '<group>'
      
      # 添加文件到目标的编译源
      target.add_file_references([file_ref])
      
      # 保存项目
      project.save
      puts '已添加: ${file_path}'
    else
      puts '错误: 无法创建组结构'
    end
  else
    puts '未找到目标 target: ${target_name}'
  end
rescue => e
  puts '错误: ' + e.message
end
"
}

# 自动检测项目结构
PROJECT_NAME=$(find_xcodeproj)
TARGET_NAME=$(find_target "$PROJECT_NAME")
INFO_PLIST_PATH=$(find_info_plist "$PROJECT_NAME")

echo "检测到的项目信息："
echo "项目名称: $PROJECT_NAME"
echo "Target名称: $TARGET_NAME"
echo "Info.plist路径: $INFO_PLIST_PATH"

# 检查是否安装了必要的 gem
if ! gem list -i xcodeproj > /dev/null 2>&1; then
    echo "正在安装 xcodeproj gem..."
    sudo gem install xcodeproj
fi

# 查找并添加新文件
echo "正在检查新文件..."
while IFS= read -r file; do
    if [ ! -z "$file" ]; then
        echo "发现新文件: $file"
        add_file_to_project "$PROJECT_NAME" "$TARGET_NAME" "$file"
    fi
done < <(find_new_files "$PROJECT_NAME")

echo "完成！"