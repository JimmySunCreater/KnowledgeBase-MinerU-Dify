查看文档转换日志方法如下：
1.ssh至MinerU-EC2
2.输入如下对应指令进行查看（注意：tail为实时刷新更新日志，也可以使用 cat 查看完整值日）
tail -f /home/ec2-user/logs/mineru_install.log #查看 MinerU安装配置日志（MinerU安装: bash /home/ec2-user/mineruinstall.sh）
tail -f /home/ec2-user/logs/mineru_api.log #查看当前运行状态日志
cat -f /home/ec2-user/logs/mineru_pdf_logs/magic_pdf_日期_时间.log  #查看某个文档转换的日志

