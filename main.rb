require 'selenium-webdriver'
require 'json'
require 'uri'
require 'benchmark'
require 'active_support/all'
require 'securerandom'

@timeout = 4

Selenium::WebDriver.logger.output = File.join('./', 'selenium.log')
Selenium::WebDriver.logger.level = :warn

driver = Selenium::WebDriver.for :chrome
driver.manage.timeouts.implicit_wait = @timeout

# Open Syllabus System of TOYO University
driver.get('https://g-sys.toyo.ac.jp/syllabus/')
sleep 1
Selenium::WebDriver::Support::Select.new(driver.find_element(:id, 'department')).select_by(:value, '1F1ZZ-2017')
driver.execute_script('document.getElementById("perPage").options[0].value = "1000"')
Selenium::WebDriver::Support::Select.new(driver.find_element(:id, 'perPage')).select_by(:value, '1000')

form_obj = driver.find_element(:name, 'form1')
form_obj.submit()

result_table = driver.find_elements(:xpath, '//*[@id="result_table"]/tbody/tr')

results = []
result_table.each do |elm|
  result = {}
  result["semester"] = elm.find_element(:xpath, './/td[2]/div').attribute("innerText")
  result["name"] = elm.find_element(:xpath, './/td[3]/div').attribute("innerText")
  result["instructor"] = elm.find_element(:xpath, './/td[4]/div').attribute("innerText")
  result["time"] = elm.find_element(:xpath, './/td[5]/div').attribute("innerText")
  result["year"] = elm.find_element(:xpath, './/td[6]/div').attribute("innerText")
#//*[@id="result_table"]/tbody/tr[1]/td[1]/div

  p result["name"]
  next if result["name"].include?("スポーツ健康科学")

  # 授業コードを取得できれば取得する
=begin
  begin
    syllabus_btn_element = elm.find_element(:xpath, './/*[@class="btn_syllabus_jp"]')
  rescue => exception
    
  end
=end
  results.append(result)
end

file = File.open("raw_results.json","w")
file.write(results.to_json)
file.close()

file = File.open("raw_results.json","r")
json_data = JSON.parse(file.read)
results = []

course_seed_file = File.open("course_label.json","r")
course_seed = JSON.parse(course_seed_file.read)

teachers = []

json_data.each do |data|
  result = {}

  #セメスター
  semester = data["semester"].split("\n")[0]
  if semester == "春学期" then
    result["quarter"] = [1,2]
  elsif semester == "秋学期" then
    result["quarter"] = [3,4]
  elsif semester == "１Ｑ" then
    result["quarter"] = [1]
  elsif semester == "２Ｑ" then
    result["quarter"] = [2]
  elsif semester == "３Ｑ" then
    result["quarter"] = [3]
  elsif semester == "４Ｑ" then
    result["quarter"] = [4]
  else
    result["quarter"] = [0]
  end

  #科目名
  subject_names = data["name"].split("\n")
  result["title"] = {}
  result["title"]["ja"] = subject_names[0]
  result["title"]["en"] = subject_names[1]

  #教員名
  curriculum_teachers = data["instructor"].split("\n")
  result["teachers"] = []

  curriculum_teachers.each do|teacher|
    result["teachers"].append(teacher.split(" / ")[0])
  end

  teachers += result["teachers"]

  #曜日
  week = data["time"].split("\n")[0].split(",")[0]
  week_seed = {
      "月" => 0,
      "火" => 1,
      "水" => 2,
      "木" => 3,
      "金" => 4,
      "土" => 5,
      "日" => 6,
      "集中" => 7
  }
  result["week"] = week_seed[week]

  #時間
  time = data["time"].split("\n")[0].split(",")[1]
  time_seed = {
      "１限" => 1,
      "２限" => 2,
      "３限" => 3,
      "４限" => 4,
      "５限" => 5,
      "６限" => 6,
      "７限" => 7,
      "集中" => 8
  }
  result["time"] = time_seed[time]

  #コース
  result["course"] = 0
  course_seed.each do |course|
    result["course"] = course["course"] if course["keywords"].filter{|title| result["title"]["ja"].include?(title)}.count != 0
  end

  #対象年次
  target_year = data["year"].split("〜")

  if target_year.count != 0 then
    result["target_year"] = (target_year[0]..target_year[1]).to_a
  else
    result["target_year"] = target_year
  end

  result["target_year"].shift if ![0,1].include?(result["course"]) #コース別授業について、一つ下の学年を含んでしまっているため

  #年度
  result["year"] = "2020"

  results.append(result)

  p result["title"]
end

file = File.new("results.json","w")
file.write(results.to_json)
file.close

#ToyoNetGの教員別担当授業照会から、確認
driver.navigate.to('https://www.toyo.ac.jp/toyonet/toyonet-g-login')
driver.execute_script('document.getElementsByName("j_username")[0].value = "";') # ToyoNet-GのユーザーID
driver.execute_script('document.getElementsByName("j_password")[0].value = "";') # ToyoNet-Gのパスワード

driver.execute_script('document.form1.submit();')

driver.navigate.to('https://g-sys.toyo.ac.jp/univision/action/in/f02/Usin025611?typeCssToApply=mobile')

# teachers = JSON.parse(File.open('teachers.json','r').read)
teachers.uniq!
teachers.each do |teacher|
  driver.execute_script("document.getElementsByName('name')[0].value = '#{teacher}'")
  driver.find_element(:name, 'Usin025610').submit()

  driver.find_element(:xpath, '//*[@id="body"]/form/table/tbody/tr[2]/td[1]/a').click

  wait = Selenium::WebDriver::Wait.new(:timeout => 100)
  wait.until {driver.find_element(:xpath, '//*[@id="body"]/form/table[2]/tbody').displayed?}

  elements = driver.find_elements(:xpath, '//*[@id="body"]/form/table[2]/tbody/tr')
  elements.each do |elm|
    next if elm == elements[0]

    campus = elm.find_element(:xpath, './/td[6]').attribute('innerText')
    next if campus != "赤羽台"

    title = elm.find_element(:xpath, './/td[4]').attribute('innerText')

    raw_schedule = elm.find_element(:xpath, './/td[2]').attribute('innerText').split("\n")
    rooms = elm.find_element(:xpath, './/td[5]').attribute('innerText').split("\n")
    schedule_count = raw_schedule.count
    for i in 1..schedule_count do
      schedule = raw_schedule[i-1]
      room = rooms[i-1]
      
      if schedule[0] == "春" or schedule[0] == "秋" then
        schedule.slice!(0)
      else
        schedule.slice!(0)
        schedule.slice!(0)
      end

      week = {
          "月" => 0,
          "火" => 1,
          "水" => 2,
          "木" => 3,
          "金" => 4,
          "土" => 5,
          "日" => 6,
          "集" => 7
      }[schedule[0]]

      time = {
          "１" => 1,
          "２" => 2,
          "３" => 3,
          "４" => 4,
          "５" => 5,
          "６" => 6,
          "７" => 7,
          nil => 8
      }[schedule[1]]

      lectures = results.select{|result| result["title"]["ja"].gsub(/　| /, '') == title}
      if lectures.select{|lecture| lecture["week"] == week and lecture["time"] == time}.count == 0 and lectures.count != 0then
        new_lecture = lectures[0].deep_dup
        new_lecture["week"] = week
        new_lecture["time"] = time

        results.append(new_lecture)

        next
      end

      lecture = lectures.select{|lecture| lecture["week"] == week and lecture["time"] == time}
      if lecture.count != 0 then
        lecture[0][:room] = room
      else
        new_lecture = {}
        new_lecture["week"] = week
        new_lecture["time"] = time
        new_lecture["room"] = room
        new_lecture["teacher"] = [teacher]
        new_lecture["title"] = {
            "ja" => title
        }

        semester = elm.find_element(:xpath, './/td[1]').attribute('innerText')
        if semester == "春" then
          new_lecture["quarter"] = [1,2]
        elsif semester == "秋" then
          new_lecture["quarter"] = [3,4]
        elsif semester == "１Ｑ" then
          new_lecture["quarter"] = [1]
        elsif semester == "２Ｑ" then
          new_lecture["quarter"] = [2]
        elsif semester == "３Ｑ" then
          new_lecture["quarter"] = [3]
        elsif semester == "４Ｑ" then
          new_lecture["quarter"] = [4]
        else
          new_lecture["quarter"] = [0]
        end

        course_seed_file = File.open("course_label.json","r")
        course_seed = JSON.parse(course_seed_file.read)

        new_lecture["course"] = 0
        course_seed.each do |course|
          new_lecture["course"] = course["course"] if course["keywords"].filter{|title| new_lecture["title"]["ja"].include?(title)}.count != 0
        end

        new_lecture["target_year"] = []

        #実習Ⅲ・実習Ⅳ・卒業研究に関しては、例外的に個別対応
        new_lecture["target_year"].append("4") if new_lecture["title"]["ja"].include?("情報連携実習Ⅳ")
        new_lecture["teacher"] = ["坂村　健"] if new_lecture["title"]["ja"].include?("情報連携実習Ⅲ")

        results.append(new_lecture)
      end
    end

  end

  driver.navigate.to('https://g-sys.toyo.ac.jp/univision/action/in/f02/Usin025611?typeCssToApply=mobile')
end


driver.close()

results.reject! {|r| r["week"] == nil}

final_file = File.new("results.json","w")
final_file.write(results.to_json)
final_file.close