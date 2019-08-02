#include "mainwindow.h"
#include "ui_mainwindow.h"

//sudo apt-get install libqt5svg5*
//sudo apt-get install jupyter

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow)
{
    ui->setupUi(this);
    ui->webView->load(QUrl("https://arcc-race.github.io/deepracer-wiki/#/"));
    ui->log->append("Log:\n");

    this->refresh();
}

MainWindow::~MainWindow()
{
    stop_process.start("/bin/sh", QStringList{stop_script});
    stop_process.waitForFinished();

    //kill all the processes
    log_analysis_process.kill();
    start_process.kill();
    stop_process.kill();


    delete ui;
}

void MainWindow::refresh(){
    //Update all the text with what is currently in the targeted files
    QFile reward_func_file(reward_func_path);
    if(!reward_func_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open reward function file: " + reward_func_file.errorString());
    } else {
        QTextStream in(&reward_func_file);
        current_reward_func = in.readAll();
        reward_func_file.close();
    }

    QFile action_space_file(action_space_path);
    if(!action_space_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open action space file: " + action_space_file.errorString());
    } else {
        QTextStream in(&action_space_file);
        current_action_space = in.readAll();
        action_space_file.close();
    }


    QFile hyperparameters_file(hyperparameters_path);
    if(!hyperparameters_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open hyperparameters file: " + hyperparameters_file.errorString());
    } else {
        QTextStream in(&hyperparameters_file);
        QString rl_file(in.readAll());
        QString text("Hyperparameters:\n");
        for(int i=0;i<hyperparams.length();i++){
            text += hyperparams[i] + " : ";
            int x=rl_file.indexOf(hyperparams[i])+hyperparams[i].length()+2; //Starts with + 2 because of "": #######," format
            while(rl_file.at(x) != '\n' && rl_file.at(x) != ','){
                text += rl_file.at(x);
                x++;
            }
            text += "\n";
        }
        current_hyperparameters = text;
        //Check if is_using pretrained
        if(rl_file.contains("# \"pretrained")){
            is_pretrained = false;
            ui->log->append("local trainer is NOT using pretrained model");
        } else {
            is_pretrained = true;
            ui->log->append("local trainer is using pretrained model");
        }
        hyperparameters_file.close();
    }


    QFile track_file(track_path);
    if(!track_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open track file: " + track_file.errorString());
    } else {
        QTextStream in(&track_file);
        current_track = in.readLine(); //First line contains track
        track_file.close();
    }

    //Set all the text on the GUI to the updated strings
    ui->reward_function->setText(current_reward_func);
    ui->action_space->setText(current_action_space);
    ui->hyper_parameters->setText(current_hyperparameters);
    ui->track_name->setText(current_track);

    is_saved = true;
}

void MainWindow::parse_logfile(){
    //Read log file and update QVector of reward per iteration
    QFile log_file(log_path);
    if(!log_file.open(QIODevice::ReadOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open log file: " + log_file.errorString());
    } else {
        int iteration = 0;
        double reward_per_iteration = 0;
        while(!log_file.atEnd()){
            QString line =log_file.readLine();
            QString marker = "SIM_TRACE_LOG:";
            QStringList list;
            if(line.contains(marker)){
                list = line.right(line.length()-line.indexOf(marker)-marker.length()).split(",");
                if(list[0].toInt() != iteration){
                    reward_per_iteration += list[log_format.indexOf("reward")].toDouble();
                    reward_per_iteration_vector.append(reward_per_iteration);
                    reward_per_iteration = 0;
                    iteration++;
                } else {
                    reward_per_iteration += list[log_format.indexOf("reward")].toDouble();
                }
            }
        }
    }
}

void MainWindow::on_save_button_clicked()
{
    //Save updates writen to the QText editor to the minio bucket and coach_rl python file
    //Update all the text with what is currently in the TextEdit

    QFile reward_func_file(reward_func_path);
    if(!reward_func_file.open(QIODevice::WriteOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open reward function file: " + reward_func_file.errorString());
    } else {
        QTextStream out(&reward_func_file);
        out << ui->reward_function->toPlainText();
        reward_func_file.close();
    }

    QFile action_space_file(action_space_path);
    if(!action_space_file.open(QIODevice::WriteOnly | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open action space file: " + action_space_file.errorString());
    } else {
        QTextStream out(&action_space_file);
        out << ui->action_space->toPlainText();
        action_space_file.close();
    }


    QFile hyperparameters_file(hyperparameters_path);
    if(!hyperparameters_file.open(QIODevice::ReadWrite | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open hyperparameters file: " + hyperparameters_file.errorString());
    } else {
        //Read existing text in the file
        QTextStream in(&hyperparameters_file);
        QString rl_file = in.readAll(); //First line contains track

        //Read the new track from the GUI
        QString text(ui->hyper_parameters->toPlainText());

        //Edit the file text
        for(int i=0;i<hyperparams.length();i++){
            QString re(hyperparams[i]);
            int param_index = rl_file.indexOf(hyperparams[i])+hyperparams[i].length();
            while(rl_file[param_index] != '\n'){
                re+=rl_file[param_index];
                param_index++;
            }
            QString new_value(hyperparams[i]+"\":");
            param_index = text.indexOf(hyperparams[i])+hyperparams[i].length()+3;
            while(text[param_index] != '\n'){
                new_value+=text[param_index];
                param_index++;
            }
            if(hyperparams[i] != "term_cond_avg_score"){
                new_value += ",";
            }
            rl_file.replace(re,new_value);
        }

        //Write edited text back into file
        QTextStream out(&hyperparameters_file);
        hyperparameters_file.resize(0); //clear the existing file
        out << rl_file; //First line contains new track name
        hyperparameters_file.close();
    }


    QFile track_file(track_path);
    if(!track_file.open(QIODevice::ReadWrite | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open track file: " + track_file.errorString());
    } else {
        //Read existing text in the file
        QTextStream in(&track_file);
        QString env_file = in.readAll(); //First line contains track

        //Read the new track from the GUI
        QString replacementText(ui->track_name->text());

        //Edit the file text
        QString first_line = "";
        int i = 0;
        while(env_file[i] !='\n'){
            first_line += env_file[i];
            i++;
        }
        QRegularExpression re(first_line);
        env_file.replace(re, replacementText);

        //Write edited text back into file
        QTextStream out(&track_file);
        track_file.resize(0); //clear the existing file
        out << env_file; //First line contains new track name
        track_file.close();
    }

    ui->log->append("Saved");
    is_saved = true;
}

void MainWindow::on_start_button_clicked()
{
    ui->log->append("Starting training...");
    //Start the simulation and training instance
    start_process.start("/bin/sh", QStringList{start_script});
    connect(&start_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
    [=]  (int exitCode)
    {
        if(exitCode){
            ui->log->append("Failed to start local training");
            start_process.kill();
        } else {
            ui->log->append("Local training started successfully");
            start_process.kill();
        }
    });

    //Start the log analysis
    if(!has_log_analysis){
        log_analysis_process.start("/bin/bash", QStringList{log_analysis_script});
        connect(&log_analysis_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
        [=]  (int exitCode)
        {
            if(exitCode && !log_analysis_url.contains("http")){
                ui->log->append("log analysis started with an ERROR");
                log_analysis_process.kill();
            } else {
                ui->log->append("log analysis started correctly");
                has_log_analysis = true;
            }
        });
        //Open up a memory manager (needs sudo password from user to actually run)
        if(!has_memory_manager){
            ui->log->append("In order to run the memory manager enter your password into the opened terminal window!");
            has_memory_manager = true;
        }
        //Access log file for updating the graph and log-analysis tools
        //    QFile latest_log_file(log_path);
        //    if(!latest_log_file.open(QIODevice::ReadOnly | QFile::Text)){
        //        QMessageBox::warning(this, "Warning", "Cannot open latest log file: " + latest_log_file.errorString());
        //        //Have user enter a file manually as backup
        //        log_path = QFileDialog::getOpenFileName(this,"Open the most recently created log file.");
        //        ui->log->append("Reading " + log_path);
        //    } else {
        //        ui->log->append("Reading latest log file");
        //    }

        //Wait 4 seconds then try to read the URL and update the web widget
        QTimer::singleShot(4000, this, SLOT(update_log_analysis_browser()));
    }

}

void MainWindow::update_log_analysis_browser()
{
    //If read is ready get parse the URL
    log_analysis_process.open();
    QString log_tool_line = log_analysis_process.readAllStandardError();
    qDebug() << log_tool_line;
    QStringList jupyter_output = log_tool_line.split('\n');
    log_analysis_url = jupyter_output[jupyter_output.length()-2].replace(" ", "");
    qDebug() << log_analysis_url;
// OLD PARSER
//    if(log_tool_line.length() > 0){
//        if(log_tool_line.contains(":8888/")){
//            //url in format [I 21:39:38.232 LabApp] http://(a320a8bc2a3d or 127.0.0.1):8888/?token=2aec87a65be6be01f999f751d4c4a0ae35e34e5a7ce004bc
//            log_tool_line = log_tool_line.split('\n')[8];
//            log_analysis_url = "http://127.0.0.1" + log_tool_line.right(log_tool_line.indexOf(":8")+3);
//        }
//    }
    log_analysis_process.close();
    if(log_analysis_url==""){
        QMessageBox::warning(this, "Warning", "Could not read log analysis tool URL, refresh to try again");
    } else {
        ui->log->append("Log analysis URL loaded: " + log_analysis_url);
        ui->webView->load(QUrl(log_analysis_url));
        //Refresh the page to get to the notebook
        QTimer::singleShot(200, this, SLOT(go_to_notebook()));
    }

}

void MainWindow::go_to_notebook(){
    QString notebook_url = log_analysis_url.left(log_analysis_url.indexOf("\?"));
    notebook_url += "notebooks/DeepRacer%20Log%20Analysis.ipynb";
    qDebug() << notebook_url;
    ui->webView->load(QUrl(notebook_url));
}

void MainWindow::on_restart_button_clicked()
{
    //Restart the simulation and training instance using model that has been training (ie using pretrained model)
    //This allows you to tweak the parameters incrementally
    ui->log->append("Restarting...");
    ui->log->append("Stoping last training instance...");
    stop_process.start("/bin/sh", QStringList{stop_script});
    connect(&stop_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
    [=]  (int exitCode)
    {
        if(exitCode){
            ui->log->append("stopped with status ERROR");
            ui->log->append("Restart failed!");
        } else {
            ui->log->append("stopped with status NORMAL");
            use_pretrained_process.start("/bin/sh", QStringList{use_pretrained_script});
            connect(&use_pretrained_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
            [=]  (int exitCode)
            {
                if(exitCode){
                    ui->log->append("pretrained model loaded with status ERROR");
                    ui->log->append("Restart failed!");
                } else {
                    ui->log->append("pretrained model loaded with status NORMAL");
                    start_process.start("/bin/sh", QStringList{start_script});
                    connect(&use_pretrained_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
                    [=]  (int exitCode)
                    {
                        if(exitCode){
                            ui->log->append("restarted trainied with status ERROR");
                            ui->log->append("Restart failed!");
                        } else {
                            ui->log->append("restarted training with status NORMAL");
                        }
                    });
                }
            });
        }
    });
}

void MainWindow::on_stop_button_clicked()
{
    //Stop the training instance
    //Stop the simulation and training instance
    QMessageBox::StandardButton reply;
    reply = QMessageBox::question(this, "Confirmation", "Are you sure you want to stop training?",QMessageBox::Yes|QMessageBox::No);
    if(reply == QMessageBox::Yes){
        ui->log->append("Stopping training...");
        stop_process.start("/bin/sh", QStringList{stop_script});
        connect(&stop_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
        [=]  (int exitCode)
        {
            if(exitCode){
                ui->log->append("training stopped with status ERROR");
                stop_process.kill();
            } else {
                ui->log->append("training stopped  with status NORMAL");
                stop_process.kill();
            }
        });
    }

}

void MainWindow::on_init_button_clicked()
{
    //Init the Repository, this also can perform recovery if something brakes
    QMessageBox::StandardButton reply;
    reply = QMessageBox::question(this, "Confirmation", "Are you sure you want to init local training? All files not saved will be lost!",QMessageBox::Yes|QMessageBox::No);
    if(reply == QMessageBox::Yes){
        init_process.start("/bin/sh", QStringList{init_script});
        connect(&init_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
        [=]  (int exitCode)
        {
            if(exitCode){
                ui->log->append("init finished with status ERROR");
                init_process.kill();
            } else {
                ui->log->append("init finished with status NORMAL");
                init_process.kill();
            }
        });

        ui->log->append("Wait while the init script runs; this may take a minute or two. Once the init script finishes you may run refresh to see reward function, action space, and hyperparameters.");
    }
}

void MainWindow::on_uploadbutton_clicked()
{
    //Upload snapshot to S3, make sure envs are set
    ui->log->append("Uploading model to S3...");
    upload_process.start("/bin/sh", QStringList{upload_script});
    connect(&upload_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
    [=]  (int exitCode)
    {
        if(exitCode){
            ui->log->append("upload finished with status ERROR, make sure that the s3 bucket and s3 prefix and filled out!");
            upload_process.kill();
        } else {
            ui->log->append("upload finished with status NORMAL");
            upload_process.kill();
        }
    });
}

void MainWindow::on_delete_button_clicked()
{
    //Delete last model
    QMessageBox::StandardButton reply;
    reply = QMessageBox::question(this, "Confirmation", "Are you sure you want to delete the most recent local model?",QMessageBox::Yes|QMessageBox::No);
    if(reply == QMessageBox::Yes){
        ui->log->append("Deleting last model...");
        delete_process.start("/bin/sh", QStringList{delete_script});
        connect(&delete_process, static_cast<void(QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
        [=]  (int exitCode)
        {
            if(exitCode){
                ui->log->append("model deleted with status ERROR");
                delete_process.kill();
            } else {
                ui->log->append("model deleted with status NORMAL");
                delete_process.kill();
            }
        });
    }
}

void MainWindow::on_refresh_button_clicked()
{
    QMessageBox::StandardButton reply;
    if(!is_saved){
        reply = QMessageBox::question(this, "Confirmation", "Are you sure you want to refresh the GUI? Not all changes have been saved!",QMessageBox::Yes|QMessageBox::No);
        if(reply == QMessageBox::Yes){
            this->refresh();
            ui->log->append("GUI refreshed.");
        } else {
            ui->log->append("GUI refresh aborted.");
        }
    } else {
        this->refresh();
        ui->log->append("GUI refreshed.");
    }
}

void MainWindow::on_use_pretrained_button_clicked()
{
    //Use pretrained lines are in the hyperparameters file
    QFile hyperparameters_file(hyperparameters_path);
    if(!hyperparameters_file.open(QIODevice::ReadWrite | QFile::Text)){
        QMessageBox::warning(this, "Warning", "Cannot open hyperparameters file: " + hyperparameters_file.errorString());
    } else {
        QTextStream in(&hyperparameters_file);
        QString hyperparameters_pretrained = in.readAll();
        int pretrained_bucket_index = hyperparameters_pretrained.indexOf("pretrained_s3_bucket")-3;
        int pretrained_prefix_index = hyperparameters_pretrained.indexOf("pretrained_s3_prefix")-3;
        int pretrained_comma_index = hyperparameters_pretrained.indexOf("# place comma here")-2;
        if(!is_pretrained){
            QMessageBox::StandardButton reply;
            reply = QMessageBox::question(this, "Confirmation", "Are you sure you want to turn ON use_pretrained? Make sure you have saved all configurations before proceeding!",QMessageBox::Yes|QMessageBox::No);
            if(reply == QMessageBox::Yes){
                hyperparameters_pretrained[pretrained_bucket_index] = ' ';
                hyperparameters_pretrained[pretrained_prefix_index] = ' ';
                hyperparameters_pretrained[pretrained_comma_index] = ',';
                is_pretrained = true;
                ui->log->append("local trainer set to use pretrained model");
                //Write edited text back into file
                QTextStream out(&hyperparameters_file);
                hyperparameters_file.resize(0); //clear the existing file
                out << hyperparameters_pretrained;
            }
        } else {
            QMessageBox::StandardButton reply;
            reply = QMessageBox::question(this, "Confirmation", "Are you sure you want turn OFF use_pretrained? Make sure you have saved all configurations before proceeding!",QMessageBox::Yes|QMessageBox::No);
            if(reply == QMessageBox::Yes){
                hyperparameters_pretrained[pretrained_bucket_index] = '#';
                hyperparameters_pretrained[pretrained_prefix_index] = '#';
                hyperparameters_pretrained[pretrained_comma_index] = ' ';
                is_pretrained = false;
                ui->log->append("local trainer will not use pretrained model");
                //Write edited text back into file
                QTextStream out(&hyperparameters_file);
                hyperparameters_file.resize(0); //clear the existing file
                out << hyperparameters_pretrained;
            }
        }
    }
    hyperparameters_file.close();
}

void MainWindow::on_reward_function_textChanged()
{
    is_saved = false;
}

void MainWindow::on_action_space_textChanged()
{
    is_saved = false;
}

void MainWindow::on_track_name_textChanged()
{
    is_saved = false;
}

void MainWindow::on_hyper_parameters_textChanged()
{
    is_saved = false;
}
