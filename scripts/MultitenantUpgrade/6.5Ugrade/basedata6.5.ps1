$applicationContext_base = @"
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:aop="http://www.springframework.org/schema/aop"
    xmlns:sec="http://www.springframework.org/schema/security"
    xmlns:context="http://www.springframework.org/schema/context"
    xmlns:tx="http://www.springframework.org/schema/tx"
    xmlns:task="http://www.springframework.org/schema/task"
    xsi:schemaLocation="
    http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans-3.0.xsd
    http://www.springframework.org/schema/tx http://www.springframework.org/schema/tx/spring-tx-3.0.xsd
    http://www.springframework.org/schema/context http://www.springframework.org/schema/context/spring-context-3.0.xsd
    http://www.springframework.org/schema/aop http://www.springframework.org/schema/aop/spring-aop-3.0.xsd
    http://www.springframework.org/schema/security http://www.springframework.org/schema/security/spring-security-3.0.xsd
    http://www.springframework.org/schema/task http://www.springframework.org/schema/task/spring-task.xsd">

    <context:component-scan base-package="com.primadesk.is"/>

    <bean class="org.springframework.orm.jpa.support.PersistenceAnnotationBeanPostProcessor" />

    <bean id="persistenceService" class="com.primadesk.is.persistence.PersistenceServiceImpl" />
    <bean id="fbPersistenceService" class="com.primadesk.is.facebookapp.persistence.FBPersistenceServiceImpl" />

    <bean id="adminFilter" class="com.primadesk.is.services.api.AdminFilter">
        <property name="persistenceService" ref="persistenceService"/>
    </bean>

    <bean id="authFilter" class="com.primadesk.is.services.api.AuthFilter">
        <property name="persistenceService" ref="persistenceService"/>
        <property name="oAuthManager" ref="oauthManager"/>
    </bean>
    
    <!-- This bean corresponds to old backup system. Need not be commented to disable. When the new
         backup system is enabled this system gets disabled automatically

    <bean id="backupService" class="com.primadesk.is.services.backup.S3BackupService">
        <property name="backupSizeThreshold" value="5368709120" />
    </bean>
    -->

    <!--
        If the value for bucket name is pd.test following are the corresponding bucket names
        for meta data and data bucket for new backup system
        data bucket for old backup system pd.test
        meta-data bucket name for old backup system pd.test.meta.data
        meta-data bucket name for new backup system pd.test.meta.data.new
        data bucket name for new backup system pd.test.new
    -->
    <bean id="s3Util" class="com.primadesk.is.services.backup.S3Util" >
        <property name="bucketName" value="pdtest.dev"/>
    </bean>

    <!-- Current backup configuration -->
    <bean id="storageService" class="com.primadesk.is.services.backup.LocalStorageService">
    </bean>

    <!--This bean corresponds to the new backup system. When enabled, all backups initiated by user
       would be handled by this system-->
    <bean id="newBackupService" class="com.primadesk.is.services.backup.BackupServiceImpl2" scope="prototype">
        <property name="backupSizeThreshold" value="5368709120" />
        <property name="storageService" ref="storageService"/>
    </bean>

    <!-- Meta-data specific class, uncomment  -->
    <bean id="mdataPersistence" class="com.primadesk.is.sys.mdata.persistence.MDataPersistenceImpl" />

    <bean id="entityManagerFactory"
        class="org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean">
        <property name="dataSource" ref="dataSource" />
        <property name="jpaVendorAdapter">
            <bean class="org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter">
                <property name="showSql" value="false" />
                <property name="databasePlatform" value="org.hibernate.dialect.PostgreSQL93Dialect"/>
            </bean>
        </property>
    </bean>
<!-- 
    <bean id="dataSource"
          class="org.springframework.jdbc.datasource.DriverManagerDataSource">
        <property name="driverClassName" value="com.mysql.jdbc.Driver" />
        <property name="url" value="jdbc:mysql://localhost/primadesk?useUnicode=true&amp;characterEncoding=utf-8" />
        <property name="username" value="primadesk" />
        <property name="password" value="primadesk" />
    </bean>
-->
    <bean id="ldapUtil" class="com.primadesk.is.ldap.util.LDAPUtil"/>
    
    <bean id="transactionManager"
        class="org.springframework.orm.jpa.JpaTransactionManager">
        <property name="entityManagerFactory" ref="entityManagerFactory" />
    </bean>
    
    <bean id="authenticationManager"
          class="com.primadesk.is.security.DBAuthenticationManager">
    </bean>
    
    <bean id="ldapAuthenticationManager"
          class="com.primadesk.is.security.LDAPAuthenticationManager">
    </bean>
    
    <bean id="userManagementBO" class="com.primadesk.is.bo.UserManagementBO">
        <property name="persistenceService" ref="persistenceService"/>
    </bean>
    
    <bean id="authenticationManagerFactory" 
    class="com.primadesk.is.security.AuthenticationManagerFactory"></bean>

    <!-- Make sure this loads at this point -->
    <bean id="pdContext"
        class="com.primadesk.is.sys.PDContextImpl">

        <!-- Unique Server node id. This name has to start with one char and the node number starting with 1-->
        <property name="serverNodeId" value="C1" />

        <!-- Max number of crawlers in the whole cluster installation -->
        <property name="maxCrawlers" value="1" />

        <!-- Overrides the user-based debugging (i.e. cancels it) -->
        <property name="userDebugOverride" value="false" />

        <!-- Initial users to debug ids right after server starts (ids separated by ,) -->
        <property name="userDebugInitialIds" value="" />

        <!-- No. of days for priority users selected for next crawl-->
        <property name="priorityUserDays" value="30" />

        <!-- Define server type PRODUCTION or STAGING or DEVELOPER -->
        <property name="serverType" value="PRODUCTION" />
        
        <!-- The backup crawler needs to wait this many hours before it can backup the bdp again -->
        <property name="minBackupInterval" value="4"/>
        
        <!-- URL of the OAuth Bounce Server, which is registered with the OAuth Service providers -->
        <property name="bounceServerPath" value="https://demo.primadesk.com/unifyle"/>
        <!-- apid url -->
        <property name="apidHostUrl" value="https://MASTERNODEIP:444"/>
        <!-- apid access key -->
        <property name="apidHostKey" value="KEYVALUE"/>

        <!-- Indexers -->
        <property name="indexers">
	        <list>
<!-- 
	            <ref bean="solrIndexer"/>
 -->
                <ref bean="netmailIndexer"/>
                 <!-- <ref bean="luceneIndexer"/> -->
	        </list>
        </property>
     </bean>
<!-- 
    <bean id="luceneIndexer">
        <!- - Lucene: Enable new alternate Lucene indexing. If false it will use Solr - ->
        <property name="luceneIndexingEnabled" value="false" />

        <!- - Lucene: Define the new Lucene index path - ->
        <property name="luceneIndexPath" value="/dev-primadesk/lucene-index" />
    </bean>
 -->
 
    <bean id="solrIndexer" class="com.primadesk.is.sys.solr.SolrIndexer">
        <!-- The host (or ip) and port of solr server -->
        <property name="solrShardHosts">
            <list>
                <value>localhost:8983/solr/search</value>
            </list>
        </property>
        <property name="solrPrimaryHost" value="http://localhost:8983/solr/search" />
        <property name="solrProtocol" value="http://" />

    </bean>
    
    <bean id="netmailIndexer" class="com.primadesk.is.sys.netmail.NetmailIndexer">
        <!-- The host (or ip) and port of solr server -->
        <property name="url" value="http://localhost:8088"/>
        <property name="persistenceService" ref="persistenceService"/>

        <!-- The host (or ip) and port of solr server -->
        
	<!-- LDAP parameters -->
    </bean>

    <!-- Task manager used for misc object copy background operations -->
    <bean id="taskManager"
          class="com.primadesk.is.sys.tasks.TaskManagerImpl">
        <property name="maxThreads" value="100" />
    </bean>

    
    <!-- Content encryptor -->
    <bean id="contentEncryptor" class="com.primadesk.is.services.PD_AES_ContentEncryptor">
    </bean>

    <!-- Content inspector -->
<!--     
    <bean id="contentInspector" class="com.primadesk.is.services.ExternalInspector">
        <property name="inspectCmdLine" value="&quot;c:\Program Files (x86)\Symantec\Scan Engine\CmdLineScanner\ssecls.exe&quot; -server localhost:1344 -mode scan -details -onerror leave &quot;${file}&quot;" />
    </bean>
-->    
<!--
     <bean id="contentInspector" class="com.primadesk.is.services.ExternalInspector">
        <property name="inspectCmdLine" value="&quot;C:\cygwin\bin\md5sum.exe&quot; &quot;${file}&quot;" />
    </bean>
-->
    <!--  Content manager -->
    <bean id="contentManager" class="com.primadesk.is.services.ContentManager">
<!-- 
        <property name="uploadChain">
            <bean class="com.primadesk.is.services.FilterChain"/>
        </property>
        <property name="downloadChain">
            <bean class="com.primadesk.is.services.FilterChain"/>
        </property>
 -->        
    </bean>

    <!-- Share Manager used to create and remove Shares -->
    <bean id="shareStorageService" class="com.primadesk.is.services.backup.LocalStorageService">
    </bean>
    
    <bean id="oauthManager"
          class="com.primadesk.is.bo.OAuthManager">
        <property name="persistenceService" ref="persistenceService"/>
    </bean>
    
    <bean id="tokenManager" class="com.primadesk.is.bo.TokenAuthManager"/>
    
    <bean id="shareManager"
          class="com.primadesk.is.bo.ShareManager" init-method="init">
        <property name="storageService" ref="shareStorageService"/>
        <property name="persistenceService" ref="persistenceService"/>
    </bean>

    <bean id="favoriteManager" class="com.primadesk.is.bo.FavoritesManager">
        <property name="persistenceService" ref="persistenceService"/>
    </bean>

    <!-- New Crawler processing sub-system  -->
    <bean id = "crawlerContext"
          class="com.primadesk.is.sys.crawler.CrawlerContextImpl" >

        <!-- Max crawlers worker thread pools for P0, P1, P2 -->
        <property name="maxCrawlersP0" value="2" />

        <!-- The system will work as before with 2 lines commented -->
<!--         <property name="maxCrawlersP1" value="2" /> -->

        <!-- enable first crawler phase to download file names/metadata.  False means go straight to downloading file content. -->
        <property name="enableMetaDataCrawl" value="false" />


        <!-- Enable background account crawling -->
        <property name="enableCrawl" value="true" />

        <!-- Enable realtime account scanning (as user logs in) -->
        <property name="enableRTScanner" value="false" />

        <!-- Enable email attachment crawler -->
        <property name="enableEmailAttachmentCrawl" value="false" />
        
        <!-- never crawl any account more frequently than every minute (value in seconds) -->
        <property name="minCrawlInterval" value="60" />
        
        <!-- enable crawler to download file content.  False means disable downloading file content. -->
        <property name="enableContentCrawl" value="true" />

        <!-- Max time allowable for the crawler to run for each account before pausing (if -1, then no limit) -->
        <property name="crawlMaxTimeSec" value="-1" />
        
        <!-- Number of concurrent downloads per crawl account -->
        <property name="downloadThreads" value="4" />
        
        <!-- Maximum document size for download in bytes -->        
        <property name="maxFileSize" value="49999999" />

        <!-- Uncomment the following section when runnign in the cloud, and provide the LDAP configuration -->

        <property name="ldapHost" value="LDAPID"/>
      
	<property name="ldapPort" value="389"/>

	<property name="ldapSsl" value="false"/>
	<property name="ldapLoginDn" value="ECLIENTDN"/>
	<property name="ldapLoginPwd" value="ECLIENTPASS"/>
	<property name="ldapContainer" value="LDAPCONTAINER"/>


    </bean>
    
    <bean id = "sharedContentCache" class="com.primadesk.is.sys.crawler.keycache.SharedContentCache">
    </bean>

    <!-- Automatic Backup sub-system -->
    <bean id="autoBackupContext" class="com.primadesk.is.sys.autobackup.AutoBackupContextImpl">
        <property name="maxAutoBackupSysPO" value="1"/>
        <property name="enableAutoBackup" value="false"/>
    </bean>

    <bean id="mdataStorageService" class="com.primadesk.is.services.backup.LocalStorageService"/>
    
    <!-- Old crawler / metadata system Queue -->
    <bean id="crawlerTasksDocs"
          class="com.primadesk.is.sys.tasks.crawlerTasksDocsImpl">
        <property name="maxThreads" value="30" />
    </bean>

    <!-- Meta-data / old crawler processing sub-system. Note if you set enable==false it will disable
    all old crawlers from running -->
    <bean id="metadataSystem"
          class="com.primadesk.is.sys.mdata.MetadataSystemImpl">

        <!-- Enable bg account crawling -->
        <property name="enableBGCrawl" value="false" />

        <!-- How many seconds to wait between crawls (a user every 5 mins) -->
        <property name="waitSecBetCrawls" value="300" />

        <!-- How many users should be taken for next crawling at same time -->
        <property name="nextCrawlableUsersLimit" value="1" />
    </bean>

    <!-- state change -->
    <bean id="ObjChangeState" class="com.primadesk.is.services.objstate.ObjChangeStateImpl" />

    <!-- campaign system -->
    <bean id="campaignSystem" class="com.primadesk.is.sys.mc.CampaignSystem">
        <property name="switchInterval" value="60"/>
    </bean>
<!-- 
     <bean id="backupDelSystem" class="com.primadesk.is.sys.autobackup.del.BackupDelSystemImpl">
        <property name="delQueueLookupinterVal" value="1"></property>
        <property name="enableBackupDelete" value="true"></property>
    </bean>
 -->
    <!--  moved to instanceContext.xml    
    <bean id="systemProperties" class="java.util.HashMap" />
    -->
        
    <tx:annotation-driven transaction-manager="transactionManager" />

    <bean id="isFirstEnter" class="com.primadesk.is.model.FirstEnter" scope="singleton">
        <property name="firstEnter" value="false"/>
    </bean>

    <bean id="crawlerConfigScheduler" class="com.primadesk.is.sys.crawler.process.CrawlerConfigScheduler">
    </bean>
<!-- 
    <bean id="filterChainProxy" class="org.springframework.security.web.FilterChainProxy">
        <sec:filter-chain-map path-type="ant">
            <sec:filter-chain pattern="/**" filters="securityContextPersistenceFilterWithASCTrue,formLoginFilter,exceptionTranslationFilter,filterSecurityInterceptor" />
        </sec:filter-chain-map>
    </bean>
-->
    <bean id="configurableSMTPEmailSender" class="com.primadesk.is.util.SMTPEMailSender"/>
    
    <bean id="emailSender" class="com.primadesk.is.util.ElasticEMailSender">
        <property name="fromAddress" value="accounts@primadesk.com"/>
        <property name="replyToAddress" value="support@primadesk.com"/>
        <property name="userName" value="admin@primadesk.com"/>
        <property name="apiKey" value="11d26331-38d3-4fed-b94e-cf5b483529e3"/>
    </bean>
    
    <task:annotation-driven executor="myExecutor" scheduler="myScheduler"/>
    <task:executor id="myExecutor" pool-size="5"/>
    <task:scheduler id="myScheduler" pool-size="10"/>

</beans>
"@