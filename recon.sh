#!/bin/bash

# my recon.sh

# Colours
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
reset="\e[0m"

# Get date
date_recon=$(date +%Y%m%d)

# List of directories
pentest_dir=${HOME}/pentest
tools_dir=${pentest_dir}/tools
wordlists_dir=${pentest_dir}/wordlists

# List of 3rd party binaries and python scripts to use in this script
amass_bin=${tools_dir}/amass/amass
aquatone_bin=${tools_dir}/aquatone/aquatone
dirsearch_bin=${tools_dir}/dirsearch/dirsearch.py
dnsrecon_bin=${tools_dir}/dnsrecon/dnsrecon.py
dnssearch_bin=${tools_dir}/dnssearch/dnssearch
gobuster_bin=${tools_dir}/gobuster/gobuster
httprobe_bin=${tools_dir}/httprobe/httprobe
massdns_bin=${tools_dir}/massdns/bin/massdns
sublist3r_bin=${tools_dir}/Sublist3r/sublist3r.py
wayback_bin=${tools_dir}/wayback/waybackurls

# List of distribuition binaries to use in this script
jq_bin=$(which jq)
host_bin=$(which host)
nmap_bin=$(which nmap)
diff_bin=$(which diff)
docker_bin=$(which docker)

# Get distribuition name
for file in '/etc/os-release' '/etc/lsb-release'; do
    if [ -s ${file} ] && [ "${file}" == "/etc/os-release" ]; then
        distribution="$(grep -E '^NAME' /etc/os-release | awk -F'=' '{print $2}')"
    elif [ -s ${file} ] && [ "${file}" == "/etc/lsb-release" ]; then
        distribution="$(grep DISTRIB_ID /etc/lsb-release | awk -F'=' '{print $2}')"
    fi
done

# Setting chromium_bin var according to the name of the distribution
if [[ ${distribution} == \"Arch\ Linux\" ]] || [[ ${distribution} == 'Kali' ]] \
    || [[ ${distribution} == \"Kali\ GNU\/Linux\" ]]; then
    chromium_bin=/usr/bin/chromium
elif [[ ${distribution} == 'Ubuntu' ]]; then
    chromium_bin=/usr/bin/chromium-browser
fi

# Verifying if all binaries there are in the system
if [[ ! -s ${amass_bin} ]] || [[ ! -s ${massdns_bin} ]] || [[ ! -s ${sublist3r_bin} ]] || \
    [[ ! -s ${httprobe_bin} ]] || [[ ! -s ${gobuster_bin} ]] || [[ ! -s ${dirsearch_bin} ]] || \
    [[ ! -s ${aquatone_bin} ]] || [[ ! -s ${chromium_bin} ]] || [[ ! -s ${dnsrecon_bin} ]] || \
    [[ ! -s ${dnssearch_bin} ]] || [[ ! -s ${wayback_bin} ]] || [[ -z ${jq_bin} ]] || \
    [[ -z ${host_bin} ]] || [[ -z ${nmap_bin} ]] || [[ -z ${diff_bin}} ]] || [[ -z ${docker_bin} ]] ; then
    echo -e "Please, run the ${yellow}prepare-box.sh${reset} to get all tools."
    exit 1
fi

# Tools parameters
aquatone_threads=5
dirsearch_docker_img="dirsearch:v0.3.8"
dirsearch_threads=50
gobuster_docker_img="gobuster:v3.0.1"
gobuster_threads=50
sublist3r_threads=40
resolver_dns="8.8.8.8"
web_extensions="php,asp,aspx,html,htmlx,shtml,txt"

# List of wordlists to use in this script
web_wordlists=(${tools_dir}/dirsearch/db/dicc.txt)
dns_wordlists=()

if [ ${#web_wordlists[@]} -eq 0 ]; then
    echo -e "Please, run the ${yellow}prepare-box.sh${reset} default wordlists!"
    exit 1
fi

# Script usage description
usage(){
    (
    echo -e "Usage: ${yellow}$0 -d domain.com${reset}"
    echo "Options: "
    echo -e "\t-d    -  specify a valid domain [needed]"
    echo -e "\t-e    -  specify excluded subdomains after all treated files"
    echo -e "\t\t ${yellow}use -e domain1.com,domain2.com${reset}"
    echo -e "\t-r    -  specify the DNS to resolve"
    echo -e "\t\t ${yellow}use -r 1.1.1.1${reset}"
    echo -e "\t-b    -  if specified the Sublist3r will do brute force, this option take a long time to finish"
    echo -e "\t\t but it brings more results, you need to specify \"yes\" and any other value will be considered as \"no\""
    echo -e "\t\t ${yellow}use -b yes${reset}"
    echo -e "\t-s    -  specify the wordlist to put in dns_wordlist array and execute gobuster and dnssearch brute force"
    echo -e "\t\t this option take a long time to finish, use this own your need, by default the array is empty"
    echo -e "\t\t and not execute gobuster and dnssearch. The success of use those tools is a good wordlist."
    echo -e "\t\t ${yellow}use -s /path/to/wordlist1,/path/to/wordlist2${reset}"
    echo -e "\t-w    -  specity more wordlist to put in web_wordlist by default we use the ${tools_dir}/dirsearch/db/dicc.txt"
    echo -e "\t\t as the first wordlist to enumerate dirs and files from website."
    echo -e "\t\t ${yellow}use -w /path/to/wordlist1,/path/to/wordlist2${reset}"
    ) 1>&2; exit 1
}

# getopts is used by shell procedures to parse positional parameters.
while getopts ":d:e:r:b:s:w:" options; do
    case "${options}" in
        d)
            domain=${OPTARG}
            ;;
        e)
            set -f
	        IFS=","
            excluded+=(${OPTARG})
	        unset IFS
            ;;
        r)
            unset resolver_dns
            resolver_dns=${OPTARG}
            ;;
        b)
            brute_sublist3r=$(echo ${OPTARG} | tr [A-Z] [a-z])
            ;;
        s)
            set -f
            IFS=","
            dns_wordlists+=(${OPTARG})
            unset IFS
            ;;
        w)
            set -f
            IFS=","
            web_wordlists+=(${OPTARG})
            unset IFS
            ;;
        *)
            usage
            ;;
    esac
done
# OPTIND The index of the next argument to be processed by the getopts builtin command (see bash man page).
shift $((OPTIND - 1))

valid_domain=$(host -t A ${domain} > /dev/null 2>&1; echo $?)

if [ -z "${domain}" ] || [ ${valid_domain} -ne 0 ]; then
    usage
    exit 1
else
    # Create all dirs necessaries to report and recon 
    if [ -d ./${domain} ]; then
        echo "This is a known target." 
    fi
    echo -n "Preparing the directories structure to work... "
    mkdir -p ./${domain}/{log,recon_${date_recon}}
    log_dir=${domain}/log
    recon_dir=${domain}/recon_${date_recon}
    mkdir -p ${recon_dir}/{tmp,report,wayback-data,aquatone,web-data}
    tmp_dir=${recon_dir}/tmp
    report_dir=${recon_dir}/report
    wayback_dir=${recon_dir}/wayback-data
    aquatone_data=${recon_dir}/aquatone
    web_data_dir=${recon_dir}/web-data
    docker_web_data=${PWD}/${web_data_dir}
    echo "Done!"

    echo "./${domain}"
    echo -e "  ├── log (${yellow}log dir for recon.sh execution${reset})"
    echo -e "  └── $(echo ${recon_dir} | awk -F "/" '{print $2}')"
    echo -e "      ├── aquatone (${yellow}aquatone output files${reset})"
    echo -e "      ├── report (${yellow}adjust function output files${reset})"
    echo -e "      ├── tmp (${yellow}subdomains recon tmp files${reset})"
    echo -e "      ├── wayback-data (${yellow}web data function for waybackurl output${reset})"
    echo -e "      └── web-data (${yellow}web data function for gobuster and dirsearch output${reset})"

    echo "Directories created."

    # Log
    execution_log=${log_dir}/recon_log-${date_recon}
fi

message() {
    echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} ${red}Recon finished on${reset} ${yellow}${domain}${reset}${red}!${reset}"
    echo -e "\t ${red}Consider to use recon-ng and theHarvester to help get more assets!${reset}"
    echo -e "\t ${red}Use Shoda.io, Censys and others.${reset}"
}

subdomains_recon(){
    if [ -d ${tmp_dir} ]; then
        echo -e "${red}Attention:${reset} The output from all tools used here will be placed in background and treated later."
        echo -e "\t   If you need look the output in execution time, you need to \"tail\" the files."
        echo -e "${green}Recon started on${reset} ${yellow}${domain}${reset}${green}!${reset}"
        echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Executing amass... "
        ${amass_bin} enum -d ${domain} > ${tmp_dir}/amass_output.txt 2>&1
        #${amass_bin} enum --passive -d ${domain} > ${tmp_dir}/amass_passive_output.txt 2>&1
        echo "Done!"

        if [ -n ${brute_sublist3r} ] && [ "${brute_sublist3r}" == "yes" ]; then
            echo -e "${red}Warning:${reset} Sublist3r take almost 30 minutes to be executed!"
            echo -e "\t If you find yourself taking longer than expected: "
            echo -e "\t ${yellow}>>${reset} check for a zombie python process;"
            echo -e "\t ${yellow}>>${reset} stop the script;"
            echo -e "\t ${yellow}>>${reset} change the default parameters of the Sublist3r in the script to a lower value;"
            echo -e "\t ${yellow}>>${reset} execute the script again;"
            echo -e "\t ${yellow}>>${reset} if the problem persists, check your internet connection."
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Executing Sublist3r... "
            ${sublist3r_bin} -n -d ${domain} -b -t ${sublist3r_threads} > ${tmp_dir}/sublist3r_output.txt 2>&1
            echo "Done!"
        else
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Executing Sublist3r... "
            ${sublist3r_bin} -n -d ${domain} > ${tmp_dir}/sublist3r_output.txt 2>&1
            echo "Done!"
        fi

        echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Executing certspotter... "
        curl -s https://certspotter.com/api/v0/certs\?domain\=${domain} | jq '.[].dns_names[]' | \
            sed 's/\"//g' | sed 's/\*\.//g' | sort -u | grep ${domain} >> ${tmp_dir}/certspotter_output.txt
        echo "Done!"

        echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Executing crt.sh... "
        curl -s https://crt.sh/?q\=%.${domain}\&output\=json | jq -r '.[].name_value' | \
            sed 's/\*\.//g' | sort -u >> ${tmp_dir}/crtsh_output.txt
        echo "Done!"

        if [ ${#dns_wordlists[@]} -gt 0 ]; then
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} We will execute gobuster and dnssearch ${#dns_wordlists[@]} time(s)."
            for list in ${dns_wordlists[@]}; do
                index=$(echo "$(printf "%s\n" "${dns_wordlists[@]}")" | grep -En "^${list}$" | awk -F":" '{print $1}')
                if [ -s ${list} ]; then
                    echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Execution number ${index}... "
                    ${gobuster_bin} dns -z -q -r ${resolver_dns} -t ${gobuster_threads} \
                        -d ${domain} -w ${list} > ${tmp_dir}/gobuster_dns_output${index}.txt 2>&1
                    ${dnssearch_bin} -consumers 600 -domain ${domain} \
                        -wordlist ${list} > ${tmp_dir}/dnssearch_output${index}.txt 2>&1
                    echo "Done!"
                else
                    echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Execution number ${index}, error: ${list} does not exist or is empty!"
                    continue
                fi
                unset index
            done
            unset list
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Execution of gobuster and dnssearch is done."
        fi
    else
        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script"
        exit 1
    fi
}

adjust_files(){
    if [ -d ${tmp_dir} ] && [ -d ${report_dir} ]; then
        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Putting all domains only in one file and getting IPs block!!!"
        if [ -s ${tmp_dir}/amass_output.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the amass output... "
            grep -Ev "Starting.*names|Querying.*|Average.*performed" ${tmp_dir}/amass_output.txt | \
                grep ${domain} | sort -u >> ${tmp_dir}/domains_tmp.txt
            grep -A 1000 "OWASP Amass.*OWASP/Amass" ${tmp_dir}/amass_output.txt >> ${report_dir}/amass_blocks_output.txt
            grep "Subdomain Name(s)" ${report_dir}/amass_blocks_output.txt | awk '{print $1}' | \
                sed '/0.0.0.0\/0/d' >> ${report_dir}/ips_blocks.txt
            echo "Done!"
        fi

        if [ -s ${tmp_dir}/amass_passive_output.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the amass passive output... "
            grep -Ev "Starting.*names|Querying.*|Average.*performed" ${tmp_dir}/amass_passive_output.txt | \
                grep ${domain} | sort -u >> ${tmp_dir}/domains_tmp.txt
            echo "Done!"
        fi

        if [ -s ${tmp_dir}/sublist3r_output.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the sublist3r output... "
            sed -i -e 's/<BR>/\n/g' -e '1,10d' ${tmp_dir}/sublist3r_output.txt 
            cat ${tmp_dir}/sublist3r_output.txt | grep -Ev "Searching.*in|Starting.*subbrute|Total.*Found" | \
                grep -Ev "Error:.*requests|Finished.*Enumeration|Warning:.*resolvers.txt" | \
                sort -u >> ${tmp_dir}/domains_tmp.txt
            echo "Done!"
        fi

        if [ -s ${tmp_dir}/certspotter_output.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the certspotter output... " 
            cat ${tmp_dir}/certspotter_output.txt | sort -u >> ${tmp_dir}/domains_tmp.txt
            echo "Done!"
        fi

        if [ -s ${tmp_dir}/crtsh_output.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the crtsh output... " 
            cat ${tmp_dir}/crtsh_output.txt | sort -u >> ${tmp_dir}/domains_tmp.txt
            echo "Done!"
        fi

        files=($(ls -1 ${tmp_dir}/gobuster_dns_output*.txt 2> /dev/null))
        if [ ${#files[@]} -gt 0 ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the gobuster dns output... "
            for file in ${files[@]}; do
                if [ -s ${file} ]; then
                    awk '{print $2}' ${file} | tr [A-Z] [a-z] | sort -u >> ${tmp_dir}/domains_tmp.txt
                else
                    echo "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up gobuster dns output error: ${file} does not exist or is empty!"
                    continue
                fi
            done
            echo "Done!"
            unset file
        fi
        unset files

        files=($(ls -1 ${tmp_dir}/dnssearch_output*.txt 2> /dev/null))
        if [ ${#files[@]} -gt 0 ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up the dnssearch output... "
            for file in ${files[@]}; do
                if [ -s ${file} ]; then
                    grep "${domain}" ${file} | awk '{print $1}' | tr [A-Z] [a-z] | sort -u >> ${tmp_dir}/domains_tmp.txt
                else
                    echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Cleanning up dnssearch output error: ${list} does not exist or is empty!"
                    continue
                fi
            done
            echo "Done"
            unset file
        fi
        unset files

        if [ -s ${tmp_dir}/domains_tmp.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Removing duplicated subdomains and unavailable domains... "
            cat ${tmp_dir}/domains_tmp.txt | tr [A-Z] [a-z] | sed -e 's/^\.//' -e 's/^-//' | \
                sed -e 's/^http:\/\///' -e 's/^https:\/\///' | sort -u > ${report_dir}/domains_all.txt
            if [ $? -eq 0 ] && [ -s ${report_dir}/domains_all.txt ]; then
                for subdomain in $(cat ${report_dir}/domains_all.txt); do
                    if [[ $(host -t A ${subdomain} | grep -E "NXDOMAIN|SERVFAIL") ]]; then
                        sed -i "/^${subdomain}$/d" ${report_dir}/domains_all.txt
                    fi
                done
                unset subdomain
            else
                echo " "
                echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Error removing duplicated subdomains and unavailable domains!"
                exit 1
            fi     
            echo "Done!"
        else
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} The file with all domains from initial recon does not exist or is empty."
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Look all files from initial recon in ${tmp_dir} and fix the problem!"
            exit 1
        fi

        if [ ${#excluded[@]} -gt 0 ] && [ -s ${report_dir}/domains_all.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Excluding the subdomains from command line option... "
            for subdomain in ${excluded[@]} ;do
                sed -i "/^${subdomain}$/d" ${report_dir}/domains_all.txt
            done
            unset subdomain
            echo "Done!"
        fi
    else
        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        exit 1
    fi
}

diff_domains(){
    if [ -d ${report_dir} ]; then 
        if [ -s ${report_dir}/domains_all.txt ]; then
            #oldest_domains_file=$(find ./${domain} -name domains_all.* -type f -printf '%T+ %p\n' | sort -u | head -n 1 | awk '{print $2}')
            oldest_domains_file=$(find ./${domain} -name domains_all.txt -type f -printf '%T+ %p\n' | sort -u | grep "$(date +%Y%m%d --date="1 day ago")" | awk '{print $2}')
            if [[ -n ${oldest_domains_file} ]]; then
                cmp -s ${oldest_domains_file} ${report_dir}/domains_all.txt
                if [ $? -ne 0 ]; then
                    echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Getting the difference between files to improve the time running recon.sh... "
                    diff -au ${oldest_domains_file} ${report_dir}/domains_all.txt | grep -E '^\+' | sed -e '/+++/d' -e 's/^+//' >> ${report_dir}/domains_diff.txt
                    if [ -s ${report_dir}/domains_diff.txt ]; then
                        mv ${report_dir}/domains_all.txt ${report_dir}/domains_all.${date_recon}
                        if [ $? -eq 0 ]; then
                            cp ${report_dir}/domains_diff.txt ${report_dir}/domains_all.txt
                        else
                            echo " "
                            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Error during move domains_all.txt to domains_all.old."
                            echo -e "\t Stopping the script!"
                            exit 1
                        fi
                    else
                        echo " "
                        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} There isn't any changes since last execution."
                        echo -e "\t Stopping the script!"
                        exit 1
                    fi
                    echo "Done!"
                else
                    echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} The files are same since last execution of recon.sh script!"
                    echo -e "\t Stopping the script!"
                    exit 1
                fi
            else
                echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} There isn't nothing in oldest_domains_file var, this the first execution of recon.sh script!"
            fi
        else
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} diff_domains function error: file ${report_dir}/domains_all.txt does not exist or is empty!"
            exit 1
        fi
    else
        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        exit 1
    fi
}

nmap_ips(){
    if [ -d ${report_dir} ]; then
        if [ -s ${report_dir}/domains_all.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Getting subdomains IP to use with nmap... "
            for subdomain in $(cat ${report_dir}/domains_all.txt); do
                host -t A ${subdomain} | grep -Ev "NXDOMAIN|SERVFAIL" | \
                    grep "has address" | sort | awk '{print $1"\t"$4}' >> ${report_dir}/domains_ips.txt
                host -t A ${subdomain} | grep -Ev "NXDOMAIN|SERVFAIL" | \
                    grep "alias" | sort | awk '{print $1"\t"$6}' | sed -e 's/\.$//'>> ${report_dir}/domains_aliases.txt
            done
            awk '{print $2}' ${report_dir}/domains_ips.txt | sort -u >> ${report_dir}/nmap_ips.txt
            unset subdomain
            echo "Done!"
        else
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} nmap_ips function error: file ${report_dir}/domains_all.txt does not exist or is empty!"
            exit 1
        fi
    
        if [ -s ${report_dir}/ips_blocks.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Getting IPs from blocks with nmap -sn \"block\"... "
            count=0
            for block in $(cat ${report_dir}/ips_blocks.txt); do
                block_file=nmap_$(echo "${block}" | sed -e 's/\//_/').txt
                cidr=$(echo ${block} | awk -F'/' '{print $2}')
                if [[ ${cidr} -ge 21 ]]; then
                    nmap -sn ${block} --exclude 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 --max-retries 3 --host-timeout 3 \
                        | grep -E "Nmap.*for" | awk '{print $6}' | sed -e 's/(//' -e 's/)//' > ${report_dir}/${block_file}
                    let count=${count}+1
                    sed -i '/^$/d' ${report_dir}/${block_file}
                    unset block_file
                else
                    continue
                fi
            done
            echo "Done!"
            if [[ ${count} -lt $(wc -l ${report_dir}/ips_blocks.txt | awk '{print $1}') ]]; then
                echo -e "${red}Warning:${reset} Just ${count} block(s) were scanned, please look at ${report_dir}/ips_blocks.txt"
                echo -e "\t and nmap blocks files to know what were excluded blocks."
            fi
            unset count
        fi
    else
        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        exit 1
    fi
}

hosts_alive(){
    if [ -d ${report_dir} ]; then
        if [ -s ${report_dir}/domains_all.txt ]; then
            echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Testing subdomains to know if it is or have web application... "
            for subdomain in $(cat ${report_dir}/domains_all.txt); do
                echo "${subdomain}" | ${httprobe_bin} \
                    -p http:8080 -p http:8443 -p http:8081 -p http:8010 -p http:8085 -p http:8086 \
                    -p http:8087 -p http:8008 | sort -u >> ${report_dir}/domains_web.txt 
            done
            unset subdomain
            echo "Done!"

            cp ${report_dir}/domains_all.txt ${report_dir}/domains_infra.txt
            if [ $? -eq 0 ] && [ -s ${report_dir}/domains_infra.txt ]; then
                echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Separating infrastructure from web application... "
                for subdomain in $(cat ${report_dir}/domains_web.txt | sed -e "s/http:\/\///" -e "s/https:\/\///" -e "s/:*.i$//" | sort -u); do
                    sed -i "/^${subdomain}$/d" ${report_dir}/domains_infra.txt
                done
                unset subdomain
                echo "Done!"
            fi
            if [ -s ${report_dir}/domains_web.txt ] && [ -s ${report_dir}/domains_infra.txt ]; then
                echo -e "\t We have $(wc -l ${report_dir}/domains_web.txt | awk '{print $1}') Web Applications URLs."
                echo -e "\t We have $(wc -l ${report_dir}/domains_infra.txt | awk '{print $1}') Infrastructure domains."
            fi
        else
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} hosts_alive function error: the ${report_dir}/domains_all.txt does not exist or is empty."
            exit 1
        fi
    else
        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        exit 1
    fi
}

web_data(){
    if [ $# != 1 ]; then
        echo "Please, especify just 1 file to get URL from."
        exit 1
    else
        subdomain_file=$1
        if [ -d ${report_dir} ] && [ -d ${wayback_dir} ] && [ -d ${web_data_dir} ]; then
            if [ ${#web_wordlists[@]} -gt 0 ] && [ -s ${subdomain_file} ]; then
                echo -e "${red}Warning:${reset} It can take a long time to execute!"
                echo -e "\t We have ${#web_wordlists[@]} wordlists and $(wc -l ${report_dir}/domains_web.txt | awk '{print $1}') urls to scan." 
                echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Web data function will use ${#web_wordlists[@]} wordlists with gobuster and dirsearch... "
                for list in ${web_wordlists[@]}; do
                    index=$(echo "$(printf "%s\n" "${web_wordlists[@]}")" | grep -En "^${list}$" | awk -F":" '{print $1}')
                    wordlist_dir=$(dirname ${list})
                    if [ -s ${list} ]; then
                        count=1
                        delay=2
                        for subdomain in $(cat ${subdomain_file}); do
                            # Running a docker proxy instance to try bypass some protection system like WAF
                            #${docker_bin} run --name proxy-${index} --rm 
                            #proxy_ip=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' proxy-${index})
                            # Mounting the file names
                            file_gobuster=gobuster_$(echo "${subdomain}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/" )_${index}.txt
                            file_dirsearch=dirsearch_$(echo "${subdomain}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/")_${index}.txt
                            # Skipping the specific wordlist from dirsearch on gobuster
                            skip_list=$(grep -E "\.\%EXT\%|\.\%EX\%" ${list} &>/dev/null; echo $?)
                            if [ ${skip_list} -eq 0 ]; then
                                ${docker_bin} run --name dirsearch_${count} -v ${docker_web_data}:${docker_web_data} -v ${wordlist_dir}:${wordlist_dir} \
                                    -d --rm "${dirsearch_docker_img}" -u ${subdomain} -e ${web_extensions} -t ${dirsearch_threads} \
                                    --random-user-agents -w ${list} --plain-text-report=${docker_web_data}/${file_dirsearch} > /dev/null 2>&1 \
                                    # --proxy ${proxy_ip}:8118
                                unset file_dirsearch
                                unset subdomain
                                sleep ${delay}
                                let count=${count}+1
                                let delay=${delay}+2
                            else
                                ${gobuster_bin} dir --delay 300ms -k -z -t ${gobuster_threads} -x ${web_extensions} -w ${list} \
                                    -u ${subdomain} &> ${web_data_dir}/${file_gobuster}
                                #docker run -it "gobuster:v3.0.1" dir
                                #sed -i "s/^..\[2K//" ${web_data_dir}/${file_gobuster}
                                sleep ${count}
                                ${docker_bin} run --name dirsearch_${count} -v ${docker_web_data}:${docker_web_data} -v ${wordlist_dir}:${wordlist_dir} \
                                    -d --rm "${dirsearch_docker_img}" -u ${subdomain} -e ${web_extensions} -t ${dirsearch_threads} \
                                    --random-user-agents -w ${list} --plain-text-report=${docker_web_data}/${file_dirsearch} > /dev/null 2>&1 \
                                    # --proxy ${proxy_ip}:8118
                                unset file_dirsearch
                                unset file_gobuster
                                unset subdomain
                                sleep ${delay}
                                let count=${count}+1
                                let delay=${delay}+2
                            fi
                        done
                        unset count
                        unset delay
                    else
                        echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Web archive function error: ${list} does not exist or is empty!"
                        continue
                    fi
                    unset index
                    unset list
                    unset wordlist_dir
                done
                echo "Done!"
            else
                echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} dirseach/goboster web_data function error: array of wordlists is empty or ${subdomain_file} does not exist or is empty. Stopping the script"
                exit 1
            fi

           # if [ -s ${subdomain_file} ]; then
           #     echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Executing wayback... "
           #     for subdomain in $(cat ${subdomain_file}); do
           #         file=wayback_$(echo "${subdomain}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/").txt
           #         echo "${subdomain}" | ${wayback_bin} &> ${wayback_dir}/${file}
           #         unset file
           #     done
           #     unset subdomain
           #     echo "Done!"
           # else
           #     echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} wayback web_data function error: ${subdomain_file} does not exist or is empty. Stopping the script"
           #     exit 1
           # fi
        else
            echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
            exit 1
        fi
        unset subdomain_file
    fi
}

robots_txt(){
    echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Looking for new URLs on robots.txt... "
    for file in $(ls -1 ${web_data_dir}/); do
        if [[ -s ${web_data_dir}/${file} ]]; then #&& [[ grep "robots.txt" "${web_data_dir}/${file}" 2> /dev/null ]]; then
            target=$(grep -E "Target:|Url:" ${web_data_dir}/${file} | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//') 
            urls=($(curl -s "${target}/robots.txt" | grep -Ev "^User-agent" | sed -e "/^Disallow \/$/d" | awk '{print $2}'))
            for url in ${urls[@]}; do
                echo "${target}${url}" >> ${tmp_dir}/robots_urls.txt
            done
            unset url
            unset urls
            unset target
        fi
        if [ -s ${tmp_dir}/robots_urls.txt ]; then
            mv ${tmp_dir}/robots_urls.txt ${report_dir}/
        fi
    done
    echo "Done!"
}

aquatone_function(){
    echo -ne "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Starting aquatone scan... "
    for file in ${report_dir}/domains_web.txt ${report_dir}/robots_urls.txt; do
        aquatone_log=${tmp_dir}/aquatone_$(basename ${file} | awk -F'.' '{print $1}').log
        aquatone_files_dir=${aquatone_data}/$(basename ${file} | awk -F'.' '{print $1}')
        if [ ! -d ${aquatone_files_dir} ]; then
            mkdir -p ${aquatone_files_dir}
            if [ $? -eq 0 ]; then
                cat ${file} | ${aquatone_bin} -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} &> ${aquatone_log}
            else
                echo " "
                echo -e "${yellow}$(date +%H:%M)${reset} ${red}>>${reset} Something got wrong, wasnt possible create directory ${aquatone_files_dir}."
                echo -e "\t Please, look what got wrong and run the script again. Stopping the script!"
                exit 1
            fi
        else
            cat ${file} | ${aquatone_bin} -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} &> ${aquatone_log}
        fi
    done
    unset aquatone_log
    unset aquatone_files_dir
    unset file
    echo "Done!"
}

#report(){
#   Falta criar a parte de report, página web, subir o server em python, etc...
#}

clean_up(){
    echo -n "Cleanning empty files... "
    echo "Done!"
    echo -n "Cleanning vars... "
    unset tmp_dir
    unset report_dir
    unset wayback_dir
    unset aquatone_data
    unset recon_dir
    unset date_recon
    unset excluded
    unset domain
    unset web_data_dir
    echo "Done!"
}

# Initiating the recon.sh script
(
#subdomains_recon
#adjust_files
#diff_domains
#nmap_ips
#hosts_alive
web_data ${report_dir}/domains_web.txt
#robots_txt
#web_data ${report_dir}/robots_urls.txt
#aquatone_function
#report
#clean_up
#message
) 2>&1 | tee -a ${execution_log}
